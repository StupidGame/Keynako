package io.github.StupidGame.azookey_flutter.conversion

import java.util.Locale

internal data class LearnedCandidate(val reading: String, val text: String, val score: Int)

private const val MAX_LEARNING_SCORE = 32
private const val MAX_CONTEXT_CHOICES = 512
private val legacyEnglishReading = Regex("[a-zA-Z']+")

internal fun learnedCandidates(learning: Map<String, Int>, english: Boolean = false): List<LearnedCandidate> =
    learning.mapNotNull { (key, count) -> learnedCandidate(key, count, english) }

private fun learnedCandidate(key: String, count: Int, english: Boolean): LearnedCandidate? {
    if (key.startsWith("context:")) return null
    val separator = key.indexOf('\t')
    if (separator <= 0 || count <= 0) return null
    var ruby = key.substring(0, separator)
    val word = key.substring(separator + 1)
    if (word.isBlank()) return null
    if (ruby.startsWith("english:")) {
        if (!english) return null
        ruby = ruby.removePrefix("english:")
    } else if (english && !legacyEnglishReading.matches(ruby)) {
        return null
    }
    if (ruby.isEmpty()) return null
    return LearnedCandidate(
        if (english) ruby.lowercase(Locale.ROOT) else katakanaToHiragana(ruby),
        word,
        count.coerceIn(1, MAX_LEARNING_SCORE),
    )
}

private fun contextPrefix(leftContext: String, reading: String): String? {
    val preceding = leftContext.trimEnd()
    if (preceding.isBlank() || reading.isBlank() || '\t' in reading) return null
    val suffix = preceding.codePoints().toArray().takeLast(4)
        .joinToString(".") { it.toString(16) }
    return "context:$suffix\t${katakanaToHiragana(reading)}\t"
}

/** A deliberate spelling choice can be recalled for the text just before the cursor. */
internal fun recordContextCandidateLearning(
    learning: MutableMap<String, Int>,
    leftContext: String,
    reading: String,
    text: String,
) {
    val prefix = contextPrefix(leftContext, reading) ?: return
    if (text.isBlank() || '\t' in text) return
    val choices = learning.filterKeys { it.startsWith(prefix) }
    val strongest = choices.values.maxOrNull()?.coerceIn(0, MAX_LEARNING_SCORE) ?: 0
    for ((key, score) in choices) {
        if (key != prefix + text) learning[key] = (score / 2).coerceAtLeast(0)
    }
    val selected = prefix + text
    learning[selected] = (strongest + 4).coerceAtMost(MAX_LEARNING_SCORE)
    val contextKeys = learning.keys.filter { it.startsWith("context:") }
    for (key in contextKeys.take((contextKeys.size - MAX_CONTEXT_CHOICES).coerceAtLeast(0))) {
        learning.remove(key)
    }
}

internal fun prioritizeContextualJapaneseCandidates(
    reading: String,
    candidates: List<String>,
    learning: Map<String, Int>,
    leftContext: String,
): List<String> {
    val prefix = contextPrefix(leftContext, reading) ?: return candidates
    return candidates.sortedByDescending { learning[prefix + it] ?: 0 }
}

/** Updates the existing score map without changing the persisted state format. */
internal fun recordCandidateLearning(
    learning: MutableMap<String, Int>,
    reading: String,
    text: String,
    english: Boolean = false,
    explicitSelection: Boolean = false,
) {
    if (reading.isBlank() || '\t' in reading || text.isBlank()) return
    val normalized = if (english) reading.lowercase(Locale.ROOT) else katakanaToHiragana(reading)
    val scores = linkedMapOf<String, Int>()
    val oldKeys = mutableListOf<String>()
    for ((key, count) in learning) {
        val entry = learnedCandidate(key, count, english) ?: continue
        if (entry.reading != normalized) continue
        oldKeys.add(key)
        val word = if (english && entry.text.equals(text, ignoreCase = true)) text else entry.text
        scores[word] = maxOf(scores[word] ?: 0, entry.score)
    }
    if (explicitSelection) {
        scores.replaceAll { word, score -> if (word == text) score else score / 2 }
        scores[text] = ((scores.values.maxOrNull() ?: 0) + 4).coerceAtMost(MAX_LEARNING_SCORE)
    } else {
        // Automatic commits provide weak evidence; a deliberate choice starts at 4.
        val existing = scores[text] ?: 0
        scores[text] = if (existing >= 4) existing else (existing + 1).coerceAtMost(3)
    }
    oldKeys.forEach(learning::remove)
    val prefix = if (english) "english:$normalized" else normalized
    scores.filterValues { it > 0 }.forEach { (word, score) -> learning["$prefix\t$word"] = score }
}

/** Reapply learned exact choices after model reranking, keeping ties stable. */
internal fun prioritizeLearnedJapaneseCandidates(
    reading: String,
    candidates: List<String>,
    learning: Map<String, Int>,
): List<String> {
    val normalized = katakanaToHiragana(reading)
    val scores = mutableMapOf<String, Int>()
    learnedCandidates(learning).filter { it.reading == normalized }.forEach {
        scores[it.text] = maxOf(scores[it.text] ?: 0, it.score)
    }
    return candidates.sortedByDescending { scores[it] ?: 0 }
}

internal fun exactLearnedJapaneseCandidates(reading: String, learning: Map<String, Int>): List<String> =
    learnedCandidates(learning)
        .filter { it.reading == katakanaToHiragana(reading) }
        .sortedByDescending { it.score }
        .map { it.text }
        .distinct()
