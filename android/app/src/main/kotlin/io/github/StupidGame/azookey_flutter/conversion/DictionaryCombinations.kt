package io.github.StupidGame.azookey_flutter.conversion

internal data class DictionaryCombinationEntry(
    val reading: String,
    val value: String,
    val importance: Int = 3,
)

private val combinationConnectors = listOf(
    "は", "が", "を", "に", "へ", "で", "と", "も", "の", "や", "か", "ね", "よ",
    "から", "まで", "より", "だけ", "など", "しか", "こそ", "でも",
    "です", "でした", "だ", "だった", "ます", "ました",
)

private fun isCombinationConnector(value: String): Boolean {
    if (value.isEmpty()) return true
    val reachable = BooleanArray(value.length + 1)
    reachable[0] = true
    for (index in value.indices) {
        if (!reachable[index]) continue
        for (connector in combinationConnectors) {
            if (value.startsWith(connector, index)) reachable[index + connector.length] = true
        }
    }
    return reachable.last()
}

/** Allow a verified full conversion to join registered words across ordinary words. */
internal fun hasLongOrdinaryGapBetweenRegisteredWords(
    reading: String,
    entries: List<DictionaryCombinationEntry>,
): Boolean {
    data class Span(val start: Int, val end: Int)
    val spans = mutableListOf<Span>()
    for (entry in entries) {
        val ruby = katakanaToHiragana(entry.reading)
        if (ruby.isEmpty() || entry.value.isEmpty()) continue
        var start = reading.indexOf(ruby)
        while (start >= 0) {
            spans.add(Span(start, start + ruby.length))
            start = reading.indexOf(ruby, start + 1)
        }
    }
    fun validGap(gap: String) = isCombinationConnector(gap) || gap.length >= 3
    for (first in spans) for (second in spans) {
        if (second.start < first.end) continue
        val gaps = listOf(
            reading.substring(0, first.start),
            reading.substring(first.end, second.start),
            reading.substring(second.end),
        )
        if (gaps.all(::validGap) && gaps.any { it.length >= 3 && !isCombinationConnector(it) }) {
            return true
        }
    }
    return false
}

/** Compose complete registered words with grammatical kana between or after them. */
internal fun dictionaryCombinationCandidates(
    reading: String,
    entries: List<DictionaryCombinationEntry>,
    limit: Int = 8,
    requireBoundaryMatches: Boolean = true,
): List<String> {
    if (reading.length < 2 || entries.isEmpty() || limit <= 0) return emptyList()
    data class Match(val end: Int, val value: String, val score: Int)
    data class Path(
        val text: String,
        val score: Int,
        val words: Int,
        val startsWithWord: Boolean,
        val pendingKana: String,
        val validConnectors: Boolean,
    )

    val matches = List(reading.length) { mutableListOf<Match>() }
    for (entry in entries) {
        val ruby = katakanaToHiragana(entry.reading)
        if (ruby.isEmpty() || entry.value.isEmpty() || ruby.length > reading.length) continue
        var start = reading.indexOf(ruby)
        while (start >= 0) {
            matches[start].add(Match(
                start + ruby.length,
                entry.value,
                ruby.length * 18 - 28 + entry.importance.coerceIn(1, 5) * 4,
            ))
            start = reading.indexOf(ruby, start + 1)
        }
    }
    if (matches.count { it.isNotEmpty() } < 2) return emptyList()

    val beams = List(reading.length + 1) { mutableListOf<Path>() }
    beams[0].add(Path("", 0, 0, false, "", true))
    fun push(end: Int, path: Path) {
        val paths = beams[end]
        paths.add(path)
        if (paths.size > 48) {
            paths.sortByDescending { it.score }
            paths.subList(16, paths.size).clear()
        }
    }
    for (index in reading.indices) {
        for (path in beams[index].sortedByDescending { it.score }.take(16)) {
            push(index + 1, Path(
                path.text + reading[index], path.score - 3, path.words,
                path.startsWithWord, path.pendingKana + reading[index], path.validConnectors,
            ))
            for (match in matches[index]) {
                push(match.end, Path(
                    path.text + match.value,
                    path.score + match.score,
                    path.words + 1,
                    path.startsWithWord || (index == 0 && path.words == 0),
                    "",
                    path.validConnectors && isCombinationConnector(path.pendingKana),
                ))
            }
        }
    }
    return beams.last().asSequence()
        .filter { it.words >= 2 && it.text != reading &&
            (!requireBoundaryMatches || (it.startsWithWord && it.validConnectors &&
                isCombinationConnector(it.pendingKana))) }
        .sortedByDescending { it.score }
        .map { it.text }
        .distinct()
        .take(limit)
        .toList()
}

/** Text formed by registered words while leaving ungrammatical kana unmatched. */
internal fun incompleteDictionaryCombinations(
    reading: String,
    entries: List<DictionaryCombinationEntry>,
    explicitExactTexts: Set<String> = emptySet(),
): Set<String> {
    val complete = dictionaryCombinationCandidates(reading, entries, 128).toSet()
    return dictionaryCombinationCandidates(
        reading, entries, 128, requireBoundaryMatches = false,
    ).filter { it !in complete && it !in explicitExactTexts }.toSet()
}

/** Covers model spellings of a partial combination as well as literal kana. */
internal fun usesMultipleRegisteredValues(
    text: String,
    registeredValues: List<String>,
    explicitExactTexts: Set<String> = emptySet(),
): Boolean = text !in explicitExactTexts && registeredValues.asSequence()
    .filter(String::isNotBlank).distinct().count { text.contains(it) } >= 2

/** A lattice conversion has consumed the whole reading, including ordinary words. */
internal fun isAllowedCombinationCandidate(
    text: String,
    trustedCompleteTexts: Set<String>,
    normalizedIncompleteTexts: Set<String>,
    blockedCombinedValues: List<String>,
    exactRegisteredTexts: Set<String>,
): Boolean {
    if (text in exactRegisteredTexts) return true
    if (katakanaToHiragana(text) in normalizedIncompleteTexts) return false
    return text in trustedCompleteTexts ||
        !usesMultipleRegisteredValues(text, blockedCombinedValues, exactRegisteredTexts)
}
