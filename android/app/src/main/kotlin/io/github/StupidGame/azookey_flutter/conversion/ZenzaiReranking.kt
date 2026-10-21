package io.github.StupidGame.azookey_flutter.conversion

internal fun hasPendingRomanSuffix(reading: String): Boolean =
    reading.lastOrNull()?.let { it in 'a'..'z' || it in 'A'..'Z' } == true

/** Spend the model budget on complete conversions, with less work for long sentences. */
internal fun zenzaiRerankingCandidates(
    reading: String,
    candidates: List<String>,
    incompleteTexts: Set<String> = emptySet(),
): List<String> {
    // A pending Roman syllable will change on the next key press. The dictionary
    // can still display its converted prefix without starting model inference.
    if (hasPendingRomanSuffix(reading)) return emptyList()
    val literal = japaneseReadingForms(reading)
    val limit = (384 / reading.length.coerceAtLeast(24)).coerceIn(2, 16)
    return candidates.asSequence().filter {
        it.isNotBlank() && it !in literal && it !in incompleteTexts
    }.distinct().take(limit).toList()
}

/** Keep a parsed kana ending ahead of a homophone that breaks it into kanji or katakana. */
internal fun preserveDictionaryKana(
    reference: String?,
    ranked: List<String>,
    preferredTexts: Set<String>,
): List<String> {
    val leading = ranked.firstOrNull() ?: return ranked
    if (reference == null || reference == leading || reference !in ranked ||
        leading in preferredTexts) return ranked
    var start = 0
    while (start < reference.length && start < leading.length && reference[start] == leading[start]) start++
    if (start == reference.length || reference[start] !in '\u3041'..'\u3096') return ranked
    var kanaStart = start
    while (kanaStart > 0 && reference[kanaStart - 1] in '\u3041'..'\u3096') kanaStart--
    var kanaEnd = start
    while (kanaEnd < reference.length && reference[kanaEnd] in '\u3041'..'\u3096') kanaEnd++
    if (kanaStart == 0 || reference[kanaStart - 1] !in '\u3400'..'\u9fff' ||
        kanaEnd - kanaStart < 2) return ranked
    var referenceEnd = reference.length
    var leadingEnd = leading.length
    while (referenceEnd > start && leadingEnd > start &&
        reference[referenceEnd - 1] == leading[leadingEnd - 1]) {
        referenceEnd--
        leadingEnd--
    }
    if (referenceEnd > kanaEnd) return ranked
    val replacement = leading.substring(start, leadingEnd)
    if (replacement.isNotEmpty() && replacement.all { it in '\u3041'..'\u3096' }) return ranked
    return listOf(reference) + ranked.filter { it != reference }
}
