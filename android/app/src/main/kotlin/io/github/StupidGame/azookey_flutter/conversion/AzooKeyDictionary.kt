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
 * class reads the same LOUDS dictionary and applies the converter's word and
 * connection scores with an N-best beam search.
 */
internal class AzooKeyDictionary(
    private val source: DictionaryAssetSource,
) {
    private data class Entry(
        val word: String,
        val ruby: String,
        val lcid: Int,
        val rcid: Int,
        val score: Float,
    )

    private data class Path(
        val text: String,
        val score: Float,
        val lastRcid: Int,
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
    private data class ConversionCacheKey(
        val reading: String,
        val additionalDictionaryVersion: String,
    )

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
        val dynamicEntries = additionalEntries.map {
            Entry(
                word = it.word,
                ruby = it.ruby.toKatakana(),
                lcid = it.lcid,
                rcid = it.rcid,
                score = it.wordWeight.toFloat(),
            )
        }
        val cacheKey = ConversionCacheKey(katakana, additionalDictionaryVersion)
        val conversions = conversionCache[cacheKey] ?: convert(
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
        return DictionaryCandidates(conversions, predictions)
    }

    private fun convert(
        reading: String,
        limit: Int,
        additionalEntries: List<Entry>,
    ): List<String> {
        val beams = Array(reading.length + 1) { mutableListOf<Path>() }
        beams[0].add(Path("", 0f, BOS_CID))

        for (start in reading.indices) {
            val previous = beams[start]
                .sortedByDescending(Path::score)
                .take(BEAM_WIDTH)
            if (previous.isEmpty()) continue

            val shard = shard(reading[start])
            val matchesByEnd = linkedMapOf<Int, MutableList<Entry>>()
            for ((end, entries) in shard?.matchingEntries(reading, start, MAX_WORD_LENGTH).orEmpty()) {
                matchesByEnd.getOrPut(end) { mutableListOf() }.addAll(entries)
            }
            for (entry in additionalEntries) {
                val end = start + entry.ruby.length
                if (entry.ruby.isNotEmpty() &&
                    end <= reading.length &&
                    reading.regionMatches(start, entry.ruby, 0, entry.ruby.length)
                ) {
                    matchesByEnd.getOrPut(end) { mutableListOf() }.add(entry)
                }
            }
            var hasSingleCharacterEntry = false
            for ((end, entries) in matchesByEnd) {
                if (end == start + 1 && entries.isNotEmpty()) hasSingleCharacterEntry = true
                appendPaths(
                    beams[end],
                    previous,
                    entries.sortedByDescending(Entry::score).take(ENTRIES_PER_READING),
                )
            }

            if (!hasSingleCharacterEntry) {
                val fallback = Entry(
                    word = reading[start].toString().toHiragana(),
                    ruby = reading[start].toString(),
                    lcid = GENERAL_NOUN_CID,
                    rcid = GENERAL_NOUN_CID,
                    score = FALLBACK_SCORE,
                )
                appendPaths(beams[start + 1], previous, listOf(fallback))
            }
        }

        val result = LinkedHashSet<String>()
        for (path in beams.last().sortedByDescending(Path::score)) {
            if (path.text.isNotBlank()) result.add(path.text)
            if (result.size >= limit) break
        }
        return result.toList()
    }

    private fun appendPaths(
        destination: MutableList<Path>,
        previous: List<Path>,
        entries: List<Entry>,
    ) {
        for (entry in entries) {
            for (path in previous) {
                destination.add(
                    Path(
                        text = path.text + entry.word,
                        score = path.score + entry.score + connectionScore(path.lastRcid, entry.lcid),
                        lastRcid = entry.rcid,
                    ),
                )
            }
        }
        if (destination.size > BEAM_TRIM_THRESHOLD) {
            val trimmed = destination
                .sortedByDescending(Path::score)
                .distinctBy { it.text to it.lastRcid }
                .take(BEAM_WIDTH)
            destination.clear()
            destination.addAll(trimmed)
        }
    }

    private fun predict(
        reading: String,
        limit: Int,
        additionalEntries: List<Entry>,
    ): List<String> {
        val entries = shard(reading.first())
            ?.predictionEntries(reading, MAX_PREDICTION_DEPTH, MAX_PREDICTION_NODES)
            .orEmpty() + additionalEntries.filter {
            it.ruby.length > reading.length && it.ruby.startsWith(reading)
        }
        return entries
            .asSequence()
            .filter { it.ruby.length > reading.length }
            .sortedByDescending(Entry::score)
            .map(Entry::word)
            .filter(String::isNotBlank)
            .distinct()
            .take(limit)
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
            data class Numeric(val lcid: Int, val rcid: Int, val score: Float)
            val numeric = ArrayList<Numeric>(count)
            repeat(count) {
                val lcid = payload.short.toInt() and 0xffff
                val rcid = payload.short.toInt() and 0xffff
                payload.short // meaning id; word/connection scoring does not need it here.
                val score = payload.float
                numeric.add(Numeric(lcid, rcid, score))
            }

            val textStart = payload.position()
            val fields = splitTabFields(bytes, textStart, end)
            val ruby = fields.firstOrNull().orEmpty()
            if (ruby.isEmpty()) return emptyList()
            return numeric.mapIndexed { index, value ->
                val word = fields.getOrNull(index + 1).orEmpty().ifEmpty { ruby }
                Entry(word, ruby, value.lcid, value.rcid, value.score)
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
        private const val GENERAL_NOUN_CID = 1285
        private const val CID_COUNT = 1319
        private const val SHARD_SHIFT = 11
        private const val LOCAL_MASK = (1 shl SHARD_SHIFT) - 1
        private const val MAX_WORD_LENGTH = 20
        private const val MAX_PREDICTION_DEPTH = 8
        private const val MAX_PREDICTION_NODES = 192
        private const val BEAM_WIDTH = 48
        private const val BEAM_TRIM_THRESHOLD = 256
        private const val ENTRIES_PER_READING = 32
        private const val FALLBACK_SCORE = -17f
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
