package io.github.StupidGame.azookey_flutter.conversion

import java.util.Locale

private val defaultEnglishPredictionWords = listOf(
    "a", "about", "after", "again", "all", "also", "always", "am", "an", "and", "any", "are",
    "as", "at", "be", "because", "been", "before", "being", "best", "but", "by", "can", "come",
    "could", "day", "did", "do", "does", "doing", "done", "down", "each", "even", "first", "for",
    "from", "get", "give", "go", "good", "great", "had", "has", "have", "he", "hello", "help",
    "her", "here", "him", "his", "how", "i", "if", "in", "into", "is", "it", "its", "just",
    "know", "like", "look", "love", "make", "me", "more", "most", "my", "need", "new", "no",
    "not", "now", "of", "ok", "okay", "on", "one", "only", "or", "other", "our", "out", "over",
    "people", "please", "really", "right", "said", "same", "see", "she", "should", "so", "some",
    "sorry", "still", "take", "thank", "thanks", "that", "the", "their", "them", "then", "there",
    "these", "they", "thing", "think", "this", "time", "to", "today", "too", "up", "us", "use",
    "very", "want", "was", "way", "we", "well", "were", "what", "when", "where", "which", "who",
    "why", "will", "with", "work", "would", "yes", "you", "your",
)

/** Keeps the typed word first and adds case-matched English prefix completions. */
internal fun englishPredictionCandidates(
    input: String,
    preferredCandidates: Iterable<String> = emptyList(),
    limit: Int = 16,
): List<String> {
    if (input.isBlank() || limit <= 0) return emptyList()
    val prefix = input.lowercase(Locale.ROOT)
    val values = linkedSetOf(input)

    fun addCandidate(candidate: String) {
        if (candidate.isBlank()) return
        values.add(matchEnglishCandidateCase(candidate, input))
    }

    preferredCandidates.forEach(::addCandidate)
    defaultEnglishPredictionWords.asSequence()
        .filter { it.length > prefix.length && it.startsWith(prefix) }
        .forEach(::addCandidate)
    return values.take(limit)
}

private fun matchEnglishCandidateCase(candidate: String, input: String): String = when {
    input.all(Char::isUpperCase) -> candidate.uppercase(Locale.ROOT)
    input.firstOrNull()?.isUpperCase() == true -> candidate.replaceFirstChar(Char::uppercase)
    else -> candidate
}

/** Chooses either the leading conversion candidate or the unconverted reading. */
internal fun compositionCommitText(
    reading: String,
    candidates: List<String>,
    useCandidate: Boolean,
): String = if (useCandidate) candidates.firstOrNull() ?: reading else reading

/** Returns dictionary values whose reading extends the text currently being composed. */
internal fun prefixPredictionValues(
    reading: String,
    entries: Iterable<Pair<String, List<String>>>,
    limit: Int,
): List<String> {
    if (reading.isEmpty() || limit <= 0) return emptyList()
    return entries.asSequence()
        .filter { (ruby, _) -> ruby.length > reading.length && ruby.startsWith(reading) }
        .flatMap { (_, values) -> values.asSequence() }
        .filter(String::isNotBlank)
        .distinct()
        .take(limit)
        .toList()
}

/** Keeps live conversion first while moving prefix predictions into the visible candidates. */
internal fun prioritizePrefixPredictions(
    conversions: List<String>,
    predictions: List<String>,
    insertIndex: Int = 2,
): List<String> {
    val insertion = insertIndex.coerceIn(0, conversions.size)
    return buildList {
        addAll(conversions.take(insertion))
        addAll(predictions)
        addAll(conversions.drop(insertion))
    }.distinct()
}
