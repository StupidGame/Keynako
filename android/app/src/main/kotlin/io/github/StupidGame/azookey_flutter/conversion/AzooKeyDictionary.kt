package io.github.StupidGame.azookey_flutter.conversion

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import kotlin.math.min

/** Reads the Apache-2.0 default dictionary used by AzooKeyKanaKanjiConverter. */
internal fun interface DictionaryAssetSource {
    fun read(relativePath: String): ByteArray
}

internal data class DictionaryCandidates(
    val conversions: List<String>,
    val predictions: List<String>,
    val predictionReadings: Map<String, String> = emptyMap(),
)

internal data class AzooKeyHotfixDictionaryEntry(
    val word: String,
    val ruby: String,
    val wordWeight: Double,
    val lcid: Int,
    val rcid: Int,
    val mid: Int,
)

/**
 * Android cannot link the Swift-only AzooKeyKanaKanjiConverter package. This
 * class reads the same LOUDS dictionary and searches scored paths by right CID.
 */
internal class AzooKeyDictionary(
    private val source: DictionaryAssetSource,
) {
    private data class Entry(
        val word: String,
        val ruby: String,
        val lcid: Int,
        val rcid: Int,
        val mid: Int,
        val score: Float,
        val additionalMask: Int = 0,
    )

    private data class Path(
        val text: String,
        val score: Float,
        val lastRcid: Int,
        val clauseMids: List<Int>,
        val additionalMask: Int = 0,
    )

    private data class ConnectionLine(
        val defaultScore: Float,
        val overrides: Map<Int, Float>,
    )

    private val characterIds: Map<Char, Int> by lazy {
        source.read("louds/charID.chid")
            .toString(Charsets.UTF_8)
            .withIndex()
            .associate { it.value to it.index }
    }
    private val shards = mutableMapOf<Char, LoudsShard?>()
    private val connectionLines = mutableMapOf<Int, ConnectionLine>()
    private val meaningScores: FloatArray by lazy {
        val bytes = runCatching { source.read("mm.binary") }.getOrDefault(byteArrayOf())
        if (bytes.size < MID_COUNT * MID_COUNT * Float.SIZE_BYTES) return@lazy floatArrayOf()
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        FloatArray(MID_COUNT * MID_COUNT) { buffer.float }
    }
    private data class ConversionCacheKey(
        val reading: String,
        val limit: Int,
        val additionalDictionaryVersion: String,
    )
    private var cachedAdditionalEntries: List<Entry> = emptyList()
    private var cachedLatticeReading = ""
    private var cachedLatticeEntries: List<Entry> = emptyList()
    private var cachedLattice: Array<MutableMap<Int, MutableList<Path>>> = emptyArray()

    private val conversionCache = object : LinkedHashMap<ConversionCacheKey, List<String>>(128, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<ConversionCacheKey, List<String>>): Boolean =
            size > 128
    }

    @Synchronized
    fun candidates(
        reading: String,
        predictionLimit: Int,
        conversionLimit: Int = 48,
        additionalEntries: List<AzooKeyHotfixDictionaryEntry> = emptyList(),
        additionalDictionaryVersion: String = "",
    ): DictionaryCandidates {
        if (reading.isBlank()) return DictionaryCandidates(emptyList(), emptyList())
        val katakana = reading.toKatakana()
        val untrackedEntries = additionalEntries.map {
            val ruby = it.ruby.toKatakana()
            Entry(
                word = it.word,
                ruby = ruby,
                lcid = it.lcid,
                rcid = it.rcid,
                mid = it.mid,
                score = it.wordWeight.toFloat(),
            )
        }
        val canKeepMasks = cachedLattice.isNotEmpty() &&
            katakana.startsWith(cachedLatticeReading) &&
            cachedLatticeEntries.map { it.copy(additionalMask = 0) } == untrackedEntries
        var usedMask = 0
        val dynamicEntries = untrackedEntries.mapIndexed { index, entry ->
            val previousMask = if (canKeepMasks) cachedLatticeEntries[index].additionalMask else 0
            if (previousMask != 0) {
                usedMask = usedMask or previousMask
                entry.copy(additionalMask = previousMask)
            } else if (entry.ruby.isNotEmpty() && katakana.contains(entry.ruby)) {
                val bit = (0 until MAX_TRACKED_ADDITIONAL_ENTRIES)
                    .firstOrNull { usedMask and (1 shl it) == 0 }
                if (bit == null) entry else {
                    val mask = 1 shl bit
                    usedMask = usedMask or mask
                    entry.copy(additionalMask = mask)
                }
            } else entry
        }
        // Callers may update entries without supplying a version. Never reuse
        // a result from a different dynamic dictionary or candidate limit.
        if (cachedAdditionalEntries != dynamicEntries) {
            conversionCache.clear()
            cachedAdditionalEntries = dynamicEntries
        }
        val cacheKey = ConversionCacheKey(katakana, conversionLimit, additionalDictionaryVersion)
        val conversions = if (conversionLimit <= 0) emptyList() else conversionCache[cacheKey] ?: convert(
            katakana,
            conversionLimit,
            dynamicEntries,
        ).also {
            conversionCache[cacheKey] = it
        }
        val predictions = if (predictionLimit > 0) {
            predict(katakana, predictionLimit, dynamicEntries)
        } else {
            emptyList()
        }
        return DictionaryCandidates(
            conversions,
            predictions.map(ReadingPrediction::text),
            predictions.associate { it.text to it.reading },
        )
    }

    private fun convert(
        reading: String,
        limit: Int,
        additionalEntries: List<Entry>,
    ): List<String> {
        val extendsCache = cachedLattice.isNotEmpty() &&
            reading.startsWith(cachedLatticeReading) && cachedLatticeEntries == additionalEntries
        val previousEnd = if (extendsCache) cachedLatticeReading.length else 0
        val lattice = if (extendsCache) {
            Array(reading.length + 1) { index ->
                cachedLattice.getOrNull(index) ?: mutableMapOf()
            }
        } else {
            Array(reading.length + 1) { mutableMapOf() }
        }
        if (!extendsCache) lattice[0][BOS_CID] = mutableListOf(Path("", 0f, BOS_CID, emptyList()))
        val longestEntry = maxOf(MAX_WORD_LENGTH, additionalEntries.maxOfOrNull { it.ruby.length } ?: 0)
        val firstStart = when {
            extendsCache && previousEnd == reading.length -> reading.length
            previousEnd >= longestEntry -> previousEnd - longestEntry + 1
            else -> 0
        }

        for (start in firstStart until reading.length) {
            val previous = lattice[start].flatMap { (contextKey, context) ->
                val limit = if (contextKey >= CID_COUNT) ADDITIONAL_PATHS_PER_CONTEXT else PATHS_PER_CONTEXT
                if (context.size > limit) trimContext(context, contextKey)
                context
            }
            if (previous.isEmpty()) continue

            val shard = shard(reading[start])
            val matchesByEnd = linkedMapOf<Int, MutableList<Entry>>()
            for ((end, entries) in shard?.matchingEntries(reading, start, MAX_WORD_LENGTH).orEmpty()) {
                if (end <= previousEnd) continue
                matchesByEnd.getOrPut(end) { mutableListOf() }.addAll(entries)
            }
            for (entry in additionalEntries) {
                val end = start + entry.ruby.length
                if (entry.ruby.isNotEmpty() && end > previousEnd &&
                    end <= reading.length &&
                    reading.regionMatches(start, entry.ruby, 0, entry.ruby.length)
                ) {
                    matchesByEnd.getOrPut(end) { mutableListOf() }.add(entry)
                }
            }
            for ((end, entries) in matchesByEnd) {
                appendPaths(
                    lattice[end],
                    previous,
                    entries.sortedByDescending(Entry::score),
                )
            }
            val ruby = reading[start].toString()
            if (start + 1 > previousEnd) {
                appendPaths(lattice[start + 1], previous, listOf(
                    Entry(ruby.toHiragana(), ruby, PROPER_NOUN_CID, PROPER_NOUN_CID, GENERAL_MID, -13f),
                    Entry(ruby, ruby, PROPER_NOUN_CID, PROPER_NOUN_CID, GENERAL_MID, -14f),
                ))
            }
        }
        cachedLatticeReading = reading
        cachedLatticeEntries = additionalEntries
        cachedLattice = lattice

        val ranked = lattice.last().values.flatten().sortedByDescending {
            it.score + connectionScore(it.lastRcid, EOS_CID) + semanticScore(it.clauseMids)
        }
        val result = LinkedHashSet<String>()
        val leading = minOf(limit, 5)
        for (path in ranked) {
            if (path.text.isNotBlank()) result.add(path.text)
            if (result.size >= leading) break
        }
        if (limit > leading) {
            // Preserve one complete spelling for each registered word. A long
            // suffix can otherwise fill the list with near-identical variants.
            for (entry in additionalEntries) {
                val mask = entry.additionalMask
                if (mask == 0) continue
                ranked.firstOrNull { it.additionalMask and mask != 0 }
                    ?.let { if (it.text.isNotBlank()) result.add(it.text) }
                if (result.size >= limit) break
            }
        }
        for (path in ranked) {
            if (result.size >= limit) break
            if (path.text.isNotBlank()) result.add(path.text)
        }
        return result.toList()
    }

    private fun appendPaths(
        destination: MutableMap<Int, MutableList<Path>>,
        previous: List<Path>,
        entries: List<Entry>,
    ) {
        for (entry in entries) {
            val touchedContexts = IntArray(1 shl MAX_TRACKED_ADDITIONAL_ENTRIES)
            var touchedCount = 0
            for (path in previous) {
                val mid = if (contributesMid(entry)) entry.mid else UNKNOWN_MID
                val clauseMids = when {
                    path.clauseMids.isEmpty() || beginsClause(path.lastRcid, entry.lcid) ->
                        path.clauseMids + mid
                    (path.clauseMids.last() == UNKNOWN_MID && entry.mid != UNKNOWN_MID) ||
                        contributesMid(entry) -> path.clauseMids.dropLast(1) + entry.mid
                    else -> path.clauseMids
                }
                val mask = path.additionalMask or entry.additionalMask
                val contextKey = entry.rcid + mask * CID_COUNT
                val context = destination.getOrPut(contextKey) { mutableListOf() }
                context.add(
                    Path(
                        text = path.text + entry.word,
                        score = path.score + entry.score + connectionScore(path.lastRcid, entry.lcid),
                        lastRcid = entry.rcid,
                        clauseMids = clauseMids,
                        additionalMask = mask,
                    ),
                )
                var touched = false
                for (index in 0 until touchedCount) {
                    if (touchedContexts[index] == contextKey) {
                        touched = true
                        break
                    }
                }
                if (!touched) touchedContexts[touchedCount++] = contextKey
            }
            for (index in 0 until touchedCount) {
                val contextKey = touchedContexts[index]
                val context = destination.getValue(contextKey)
                if (context.size > CONTEXT_TRIM_THRESHOLD) trimContext(context, contextKey)
            }
        }
    }

    private fun trimContext(context: MutableList<Path>, contextKey: Int) {
        val limit = if (contextKey >= CID_COUNT) ADDITIONAL_PATHS_PER_CONTEXT else PATHS_PER_CONTEXT
        val best = context.sortedByDescending(Path::score).take(limit)
        context.clear()
        context.addAll(best)
    }

    private fun semanticScore(clauseMids: List<Int>): Float {
        if (clauseMids.size < 2) return 0f
        val scores = meaningScores
        if (scores.isEmpty()) return 0f
        var previous = UNKNOWN_MID
        var total = 0f
        for (mid in clauseMids) {
            if (previous in 0 until MID_COUNT && mid in 0 until MID_COUNT &&
                previous != UNKNOWN_MID && mid != UNKNOWN_MID) {
                total += scores[previous * MID_COUNT + mid]
            }
            previous = mid
        }
        return total
    }

    private fun beginsClause(former: Int, latter: Int): Boolean {
        val latterType = wordType(latter)
        if (latterType == 3 || wordType(former) == 3) return false
        return latterType in 0..1 && wordType(former) != 0
    }

    private fun contributesMid(entry: Entry): Boolean {
        fun special(cid: Int) = cid in 895..1280 || cid in 1297..1305
        return special(entry.lcid) || special(entry.rcid) ||
            wordType(entry.lcid) == 1 || wordType(entry.rcid) == 1
    }

    private fun wordType(cid: Int): Int = when {
        cid == BOS_CID || cid == EOS_CID -> 3
        cid == 1315 || cid == 6 || cid in 557..560 -> 0
        cid in 561..867 || cid in 1283..1296 || cid in 1306..1309 ||
            cid in 11..52 || cid in 555..556 || cid in 1281..1282 ||
            cid == 1314 || cid in 1..5 || cid == 9 -> 1
        else -> 2
    }

    private fun predict(
        reading: String,
        limit: Int,
        additionalEntries: List<Entry>,
    ): List<ReadingPrediction> {
        val entries = shard(reading.first())
            ?.predictionEntries(reading, MAX_PREDICTION_DEPTH, MAX_PREDICTION_NODES)
            .orEmpty() + additionalEntries.filter {
            it.ruby.length > reading.length && it.ruby.startsWith(reading)
        }
        return entries
            .asSequence()
            .filter { it.ruby.length > reading.length }
            .sortedByDescending {
                // Prefixes can still grow into a phrase. Boundary scores help
                // reject unfinished inflections without drowning word frequency.
                it.score + 0.5f * (connectionScore(BOS_CID, it.lcid) +
                    connectionScore(it.rcid, EOS_CID)) -
                    (it.ruby.length - reading.length) * 0.5f
            }
            .filter { it.word.isNotBlank() }
            .distinctBy(Entry::word)
            .take(limit)
            .map { ReadingPrediction(it.ruby.toHiragana(), it.word) }
            .toList()
    }

    private fun connectionScore(former: Int, latter: Int): Float {
        if (former !in 0 until CID_COUNT || latter !in 0 until CID_COUNT) return DEFAULT_CONNECTION_SCORE
        val line = connectionLines.getOrPut(former) {
            runCatching { parseConnectionLine(source.read("cb/$former.binary")) }
                .getOrElse { ConnectionLine(DEFAULT_CONNECTION_SCORE, emptyMap()) }
        }
        return line.overrides[latter] ?: line.defaultScore
    }

    private fun parseConnectionLine(bytes: ByteArray): ConnectionLine {
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        var defaultScore = DEFAULT_CONNECTION_SCORE
        val overrides = mutableMapOf<Int, Float>()
        while (buffer.remaining() >= 8) {
            val key = buffer.int
            val value = buffer.float
            if (key == -1) defaultScore = value else if (key in 0 until CID_COUNT) overrides[key] = value
        }
        return ConnectionLine(defaultScore, overrides)
    }

    private fun shard(first: Char): LoudsShard? = shards.getOrPut(first) {
        val identifier = escapedIdentifier(first.toString())
        runCatching {
            LoudsShard(
                identifier = identifier,
                loudsBytes = source.read("louds/$identifier.louds"),
                nodeCharacters = source.read("louds/$identifier.loudschars2"),
                characterIds = characterIds,
                source = source,
            )
        }.getOrNull()
    }

    private class LoudsShard(
        private val identifier: String,
        loudsBytes: ByteArray,
        private val nodeCharacters: ByteArray,
        private val characterIds: Map<Char, Int>,
        private val source: DictionaryAssetSource,
    ) {
        private val childStarts = IntArray(nodeCharacters.size)
        private val childEnds = IntArray(nodeCharacters.size)
        private val entriesByNode = mutableMapOf<Int, List<Entry>>()
        private val dataShards = mutableMapOf<Int, ByteArray?>()

        init {
            decodeChildRanges(loudsBytes)
        }

        fun matchingEntries(
            text: String,
            start: Int,
            maxLength: Int,
        ): List<Pair<Int, List<Entry>>> {
            var node = ROOT_NODE
            val result = mutableListOf<Pair<Int, List<Entry>>>()
            val end = min(text.length, start + maxLength)
            for (index in start until end) {
                val charId = characterIds[text[index]] ?: break
                node = child(node, charId) ?: break
                val entries = entries(node)
                if (entries.isNotEmpty()) result.add(index + 1 to entries)
            }
            return result
        }

        fun predictionEntries(
            prefix: String,
            maxDepth: Int,
            maxNodes: Int,
        ): List<Entry> {
            var node = ROOT_NODE
            for (character in prefix) {
                val charId = characterIds[character] ?: return emptyList()
                node = child(node, charId) ?: return emptyList()
            }
            val queue = ArrayDeque<Pair<Int, Int>>()
            children(node).forEach { queue.addLast(it to 1) }
            val result = mutableListOf<Entry>()
            var visited = 0
            while (queue.isNotEmpty() && visited < maxNodes) {
                val (current, depth) = queue.removeFirst()
                visited += 1
                result.addAll(entries(current))
                if (depth < maxDepth) {
                    children(current).forEach { queue.addLast(it to depth + 1) }
                }
            }
            return result
        }

        private fun child(parent: Int, charId: Int): Int? {
            if (parent !in childStarts.indices) return null
            for (index in childStarts[parent] until childEnds[parent]) {
                if (index in nodeCharacters.indices && (nodeCharacters[index].toInt() and 0xff) == charId) {
                    return index
                }
            }
            return null
        }

        private fun children(parent: Int): IntRange {
            if (parent !in childStarts.indices || childStarts[parent] >= childEnds[parent]) return IntRange.EMPTY
            return childStarts[parent] until childEnds[parent]
        }

        private fun entries(node: Int): List<Entry> = entriesByNode.getOrPut(node) {
            val shardIndex = node shr SHARD_SHIFT
            val bytes = dataShards.getOrPut(shardIndex) {
                runCatching { source.read("louds/$identifier$shardIndex.loudstxt3") }.getOrNull()
            } ?: return@getOrPut emptyList()
            parseEntries(bytes, node and LOCAL_MASK)
        }

        private fun decodeChildRanges(bytes: ByteArray) {
            val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            var ones = 0
            var zeros = 0
            var segmentStart = 1
            while (buffer.remaining() >= Long.SIZE_BYTES && zeros < nodeCharacters.size) {
                val word = buffer.long
                for (shift in 63 downTo 0) {
                    if (((word ushr shift) and 1L) != 0L) {
                        ones += 1
                    } else {
                        if (zeros < childStarts.size) {
                            childStarts[zeros] = segmentStart
                            childEnds[zeros] = ones + 1
                        }
                        zeros += 1
                        segmentStart = ones + 1
                        if (zeros >= nodeCharacters.size) return
                    }
                }
            }
        }

        private fun parseEntries(bytes: ByteArray, localIndex: Int): List<Entry> {
            if (bytes.size < 6) return emptyList()
            val header = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            val slotCount = header.short.toInt() and 0xffff
            if (localIndex !in 0 until slotCount || bytes.size < 2 + slotCount * 4) return emptyList()
            val start = header.getInt(2 + localIndex * 4)
            val end = if (localIndex == slotCount - 1) bytes.size else header.getInt(2 + (localIndex + 1) * 4)
            if (start < 0 || end > bytes.size || start + 2 > end) return emptyList()

            val payload = ByteBuffer.wrap(bytes, start, end - start).order(ByteOrder.LITTLE_ENDIAN)
            val count = payload.short.toInt() and 0xffff
            if (count == 0 || payload.remaining() < count * 10) return emptyList()
            data class Numeric(val lcid: Int, val rcid: Int, val mid: Int, val score: Float)
            val numeric = ArrayList<Numeric>(count)
            repeat(count) {
                val lcid = payload.short.toInt() and 0xffff
                val rcid = payload.short.toInt() and 0xffff
                val mid = payload.short.toInt() and 0xffff
                val score = payload.float
                numeric.add(Numeric(lcid, rcid, mid, score))
            }

            val textStart = payload.position()
            val fields = splitTabFields(bytes, textStart, end)
            val ruby = fields.firstOrNull().orEmpty()
            if (ruby.isEmpty()) return emptyList()
            return numeric.mapIndexedNotNull { index, value ->
                val word = fields.getOrNull(index + 1).orEmpty().ifEmpty { ruby }
                val score = minOf(0f, value.score)
                // Match DicdataStore.shouldBeRemoved in the Swift converter.
                // Weak single-character readings otherwise crowd out common words.
                if (score - DICTIONARY_THRESHOLD < 2f / word.codePointCount(0, word.length)) {
                    null
                } else {
                    Entry(word, ruby, value.lcid, value.rcid, value.mid, score)
                }
            }
        }

        private fun splitTabFields(bytes: ByteArray, start: Int, end: Int): List<String> {
            val fields = mutableListOf<String>()
            var fieldStart = start
            for (index in start..end) {
                if (index == end || bytes[index] == '\t'.code.toByte()) {
                    fields.add(bytes.copyOfRange(fieldStart, index).toString(Charsets.UTF_8))
                    fieldStart = index + 1
                }
            }
            return fields
        }
    }

    companion object {
        private const val ROOT_NODE = 1
        private const val BOS_CID = 0
        private const val EOS_CID = 1316
        private const val PROPER_NOUN_CID = 1288
        private const val GENERAL_MID = 501
        private const val UNKNOWN_MID = 500
        private const val MID_COUNT = 502
        private const val CID_COUNT = 1319
        private const val SHARD_SHIFT = 11
        private const val LOCAL_MASK = (1 shl SHARD_SHIFT) - 1
        private const val MAX_WORD_LENGTH = 20
        private const val MAX_PREDICTION_DEPTH = 8
        private const val MAX_PREDICTION_NODES = 192
        private const val PATHS_PER_CONTEXT = 4
        private const val ADDITIONAL_PATHS_PER_CONTEXT = 1
        private const val CONTEXT_TRIM_THRESHOLD = 16
        private const val MAX_TRACKED_ADDITIONAL_ENTRIES = 4
        private const val DICTIONARY_THRESHOLD = -17f
        private const val DEFAULT_CONNECTION_SCORE = -25f

        private fun escapedIdentifier(value: String): String = value
            .toCharArray()
            .joinToString(separator = "_", prefix = "[", postfix = "]") {
                String.format(Locale.ROOT, "%04X", it.code)
            }

        private fun String.toKatakana(): String = buildString(length) {
            for (character in this@toKatakana) {
                append(if (character.code in 0x3041..0x3096) (character.code + 0x60).toChar() else character)
            }
        }

        private fun String.toHiragana(): String = buildString(length) {
            for (character in this@toHiragana) {
                append(if (character.code in 0x30a1..0x30f6) (character.code - 0x60).toChar() else character)
            }
        }
    }
}
