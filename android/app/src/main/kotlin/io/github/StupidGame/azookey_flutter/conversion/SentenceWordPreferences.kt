package io.github.StupidGame.azookey_flutter.conversion

/** Boundaries from a full dictionary parse, in UTF-16 offsets. */
internal data class ConversionWordSpan(
    val readingStart: Int,
    val readingEnd: Int,
    val textStart: Int,
    val textEnd: Int,
)

internal data class SentenceWordPreference(
    val reading: String,
    val text: String,
    val learned: Boolean = false,
    val weight: Double = 0.0,
)

/** Replaces whole parsed words, retaining every other part of the candidate. */
internal fun preferredSentenceSpelling(
    reading: String,
    text: String,
    spans: List<ConversionWordSpan>,
    preferences: List<SentenceWordPreference>,
): String? {
    if (spans.isEmpty() || preferences.isEmpty()) return null
    val normalized = katakanaToHiragana(reading)
    val boundaries = mutableMapOf(0 to 0)
    for (span in spans) boundaries[span.readingEnd] = span.textEnd
    data class Match(val start: Int, val end: Int, val preference: SentenceWordPreference)
    val matches = mutableListOf<Match>()
    for (preference in preferences) {
        val ruby = katakanaToHiragana(preference.reading)
        if (ruby.isBlank() || preference.text.isBlank()) continue
        var start = normalized.indexOf(ruby)
        while (start >= 0) {
            val textStart = boundaries[start]
            val textEnd = boundaries[start + ruby.length]
            if (textStart != null && textEnd != null && textStart < textEnd) {
                matches.add(Match(textStart, textEnd, preference))
            }
            start = normalized.indexOf(ruby, start + 1)
        }
    }
    val chosen = mutableListOf<Match>()
    for (match in matches.sortedWith(
        compareBy<Match> { it.preference.learned }
            .thenByDescending { it.preference.reading.length }
            .thenByDescending { it.preference.weight }
            .thenByDescending { text.substring(it.start, it.end) == it.preference.text }
            .thenBy { it.start },
    )) {
        if (chosen.none { match.start < it.end && it.start < match.end }) chosen.add(match)
    }
    if (chosen.isEmpty()) return null
    var result = text
    for (match in chosen.sortedByDescending { it.start }) {
        result = result.replaceRange(match.start, match.end, match.preference.text)
    }
    return result
}
