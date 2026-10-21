package io.github.StupidGame.azookey_flutter.conversion

internal fun hasPendingRomanSuffix(reading: String): Boolean =
    reading.lastOrNull()?.let { it in 'a'..'z' || it in 'A'..'Z' } == true

/** Full-width kana can be the intended spelling; half-width literal output stays a fallback. */
internal fun completeZenzaiCandidate(
    reading: String,
    text: String,
    baseCandidates: List<String>,
    incompleteTexts: Set<String>,
    validateGenerated: (String) -> Boolean,
): String? {
    val hiragana = katakanaToHiragana(reading)
    val kanaSpellings = setOf(hiragana, hiraganaToKatakana(hiragana))
    val fallback = japaneseReadingForms(reading) - kanaSpellings
    return text.takeIf {
        it.isNotBlank() && it !in incompleteTexts && it !in fallback &&
            (it in baseCandidates || validateGenerated(it))
    }
}

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
    if (start == reference.length) return ranked
    val katakanaWord = reference[start] in '\u30a1'..'\u30fa'
    fun inKana(char: Char) = if (katakanaWord) char in '\u30a1'..'\u30fa' || char == 'ー'
        else char in '\u3041'..'\u3096'
    if (!inKana(reference[start])) return ranked
    var kanaStart = start
    while (kanaStart > 0 && inKana(reference[kanaStart - 1])) kanaStart--
    var kanaEnd = start
    while (kanaEnd < reference.length && inKana(reference[kanaEnd])) kanaEnd++
    if (katakanaWord) {
        if (kanaEnd - kanaStart < 3) return ranked
    } else if (kanaStart == 0 || reference[kanaStart - 1] !in '\u3400'..'\u9fff' ||
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
    if (replacement.isNotEmpty() && replacement.all(::inKana)) return ranked
    return listOf(reference) + ranked.filter { it != reference }
}

/** Run after every ranking source, including contextual learning and pending lookups. */
internal fun finalJapaneseCandidateSpellings(
    candidates: List<String>,
    canonicalConversion: String?,
    registeredTexts: Set<String> = emptySet(),
    learnedTexts: Set<String> = emptySet(),
): List<String> = preserveDictionaryKana(
    canonicalConversion,
    prioritizeHiraganaVariants(candidates, registeredTexts),
    registeredTexts + learnedTexts,
)
