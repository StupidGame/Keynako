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

/** Registered completions precede learned ones; English composition stays literal. */
internal fun englishPredictionCandidates(
    input: String,
    preferredCandidates: Iterable<String> = emptyList(),
    limit: Int = 16,
    learning: Map<String, Int> = emptyMap(),
): List<String> {
    if (input.isBlank() || limit <= 0) return emptyList()
    val prefix = input.lowercase(Locale.ROOT)
    val registered = preferredCandidates.filter(String::isNotBlank)
        .map { matchEnglishCandidateCase(it, input) }
    val scores = mutableMapOf<String, Int>()
    for (entry in learnedCandidates(learning, english = true)) {
        if (!entry.reading.startsWith(prefix) && !entry.text.lowercase(Locale.ROOT).startsWith(prefix)) continue
        val word = matchEnglishCandidateCase(entry.text, input)
        scores[word] = maxOf(scores[word] ?: 0, entry.score)
    }
    val defaults = defaultEnglishPredictionWords.asSequence()
        .filter { it.length > prefix.length && it.startsWith(prefix) }
        .map { matchEnglishCandidateCase(it, input) }
    return (registered + scores.keys.sortedByDescending { scores[it] } + listOf(input) + defaults.toList())
        .distinct().take(limit)
}

/**
 * Applies a case-only character form without completing the current
 * composition, including from custom English layouts whose mode is Japanese.
 */
internal fun caseConvertedComposition(input: String, form: String?): String? = when (form) {
    "uppercase" -> input.uppercase(Locale.ROOT)
    "lowercase" -> input.lowercase(Locale.ROOT)
    else -> null
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
    selectedIndex: Int = 0,
): String = if (useCandidate) candidates.getOrNull(selectedIndex) ?: candidates.firstOrNull() ?: reading else reading

/** Give longer readings enough room to finish; capped requests are reranked without generation. */
internal fun zenzaiGenerationTokenBudget(readingLength: Int, effort: Int): Int {
    val limit = when (effort) {
        0 -> 64
        2 -> 128
        else -> 96
    }
    return (readingLength * 3 + 16).coerceIn(16, limit)
}

internal fun shouldGenerateZenzaiCandidate(readingLength: Int, maxTokens: Int): Boolean =
    readingLength * 3 + 16 <= maxTokens

/** A complete conversion may lead live input; completions and bare kana may not. */
internal fun bestLiveJapaneseConversion(
    reading: String,
    completeConversions: Set<String>,
    ranked: Iterable<String>,
): String? {
    val hiragana = katakanaToHiragana(reading)
    val katakana = hiraganaToKatakana(hiragana)
    return ranked.firstOrNull { it in completeConversions && it != hiragana && it != katakana }
}

/** Keep an uncommitted single kana literal until enough context has been typed. */
internal fun preferSingleKanaReading(
    reading: String,
    candidates: List<String>,
    hasExactRegistration: Boolean,
): List<String> {
    if (reading.length != 1 || reading[0] !in '\u3041'..'\u3096' ||
        hasExactRegistration || reading !in candidates) return candidates
    return listOf(reading) + candidates.filter { it != reading }
}

/** Keep both literal kana spellings in the visible candidate row. */
internal fun keepKanaCandidatesVisible(reading: String, candidates: List<String>): List<String> {
    val hiragana = katakanaToHiragana(reading)
    val katakana = hiraganaToKatakana(hiragana)
    if (hiragana.isBlank() || hiragana == katakana) return candidates
    val visible = candidates.toMutableList()
    for ((literal, latestIndex) in listOf(hiragana to 3, katakana to 4)) {
        val currentIndex = visible.indexOf(literal)
        if (currentIndex in 0..latestIndex) continue
        if (currentIndex >= 0) visible.removeAt(currentIndex)
        visible.add(minOf(latestIndex, visible.size), literal)
    }
    return visible
}

/** The editor includes the active composition in text before the cursor. */
internal fun precedingTextBeforeComposition(
    beforeCursor: String,
    composingText: String,
    maxLength: Int,
): String {
    val preceding = if (composingText.isNotEmpty() && beforeCursor.endsWith(composingText)) {
        beforeCursor.dropLast(composingText.length)
    } else beforeCursor
    return preceding.takeLast(maxLength.coerceAtLeast(0))
}

/** Keep a new model suggestion visible without letting it displace common dictionary results. */
internal fun placeNovelGeneratedCandidate(
    ranked: List<String>,
    generated: String,
    established: Set<String>,
): List<String> {
    if (generated.isEmpty() || generated in established || generated !in ranked) return ranked
    val common = ranked.filter { it != generated }
    val insertion = minOf(3, common.size)
    return common.take(insertion) + generated + common.drop(insertion)
}

/** Returns dictionary values whose reading extends the text currently being composed. */
internal data class ReadingPrediction(
    val reading: String,
    val text: String,
    val importance: Int = 3,
)

/** Learned longer readings stay complete when a user has typed only their prefix. */
internal fun learnedJapanesePrefixPredictions(
    reading: String,
    learning: Map<String, Int>,
    exclude: Set<String> = emptySet(),
    limit: Int = 4,
): List<LearnedCandidate> {
    if (reading.isEmpty() || limit <= 0) return emptyList()
    val normalized = katakanaToHiragana(reading)
    return learnedCandidates(learning).asSequence()
        .filter {
            it.reading.length > normalized.length && it.reading.startsWith(normalized) &&
                it.text.isNotBlank() && it.text !in exclude
        }
        .sortedWith(compareByDescending<LearnedCandidate> { it.score }.thenBy { it.reading.length })
        .distinctBy { it.text }
        .take(limit)
        .toList()
}

/** Keep completions visible after the model reranks candidates, without using one for live text. */
internal fun rerankedJapaneseCandidates(
    reading: String,
    ranked: List<String>,
    baseCandidates: List<String>,
    predictionReadings: Map<String, String>,
    learning: Map<String, Int>,
    dictionaryCandidates: List<String> = emptyList(),
    learningCandidates: List<String> = emptyList(),
    partialCandidates: Set<String> = emptySet(),
    preferredZenzaiCandidate: String? = null,
    exactRegistrationTexts: Set<String> = emptySet(),
    dictionaryLedLiteral: Boolean = baseCandidates.firstOrNull() == reading,
): List<String> {
    val learnedPrefixes = learnedJapanesePrefixPredictions(reading, learning)
    val predictionTexts = predictionReadings.keys + learnedPrefixes.map { it.text }
    val katakana = hiraganaToKatakana(katakanaToHiragana(reading))
    val fallback = setOf(reading, katakana)
    val baseSet = baseCandidates.toSet()
    fun complete(value: String) = value.isNotBlank() && value !in predictionTexts &&
        value !in partialCandidates && value !in fallback
    // Zenzai's order applies to candidates grounded in the dictionary lattice.
    // A generated word joins after the first few complete paths.
    val established = ranked.filter { complete(it) && it in baseSet }
    val novel = ranked.filter { complete(it) && it !in baseSet }
    val preferred = preferredZenzaiCandidate?.takeIf { it in established }
    val exact = (listOfNotNull(preferred) + established +
        dictionaryCandidates.filter(::complete) + learningCandidates.filter(::complete) +
        baseCandidates.filter(::complete)).distinct()
    val full = (exact.take(3) + novel + exact.drop(3)).distinct()
    val prominentPredictions = (baseCandidates.filter { it in predictionTexts } +
        learnedPrefixes.map { it.text }).distinct().take(4)
    val registeredComplete = (dictionaryCandidates + learningCandidates)
        .filter(::complete).toSet()
    val predictionInsertion = maxOf(3, full.indexOfLast { it in registeredComplete } + 1)
        .coerceAtMost(full.size)
    val otherPredictions = (ranked + dictionaryCandidates + learningCandidates + baseCandidates)
        .filter { it in predictionTexts && it !in prominentPredictions }.distinct()
    val partial = (ranked + dictionaryCandidates + learningCandidates + baseCandidates)
        .filter { it in partialCandidates && it !in predictionTexts }.distinct()
    val ordered = (full.take(predictionInsertion) + prominentPredictions +
        full.drop(predictionInsertion) +
        otherPredictions + partial + baseCandidates.filter { it in fallback } +
        ranked.filter { it in fallback }).filter(String::isNotBlank).distinct()
    val strongLearnedWords = learnedCandidates(learning).filter {
        it.reading == katakanaToHiragana(reading) && it.score >= 4
    }.mapTo(mutableSetOf()) { it.text }
    val explicitlyPreferred = exactRegistrationTexts + strongLearnedWords
    val exactRegistration = dictionaryCandidates.any { complete(it) } ||
        explicitlyPreferred.isNotEmpty()
    // A kana-only word or phrase can be a complete conversion. If the
    // dictionary itself puts it first, do not demote it as a raw fallback.
    val keepLiteral = (reading.length <= 2 && prominentPredictions.isEmpty()) ||
        (reading.length > 2 && dictionaryLedLiteral)
    if (baseCandidates.firstOrNull() == reading && keepLiteral && !exactRegistration) {
        return listOf(reading) + ordered.filter { it != reading }
    }
    val leading = ordered.firstOrNull()
    val ordinarySpelling = when {
        // A bare negative question is more useful than a medical department
        // when the composition has no surrounding words. Keep a deliberate
        // user choice ahead of this default.
        reading == "ないか" && "無いか" in ordered -> "無いか"
        // The model sometimes promotes a mixed-script fragment or an uppercase
        // alias over the ordinary katakana spelling of the same complete reading.
        baseCandidates.firstOrNull() == katakana && katakana in ordered &&
            leading != null && (leading.any { it in 'A'..'Z' } ||
                (leading.any { it in '\u3041'..'\u3096' } &&
                    leading.any { it in '\u30a1'..'\u30f6' })) -> katakana
        else -> null
    }
    val stable = if (ordinarySpelling != null && leading !in explicitlyPreferred) {
        listOf(ordinarySpelling) + ordered.filter { it != ordinarySpelling }
    } else ordered
    val dictionaryFirst = baseCandidates.firstOrNull()
    // The dictionary has already parsed the words before 「付き」. Keep that
    // complete path ahead of a model-ranked suffix with the same word group.
    val attachedSuffix = dictionaryFirst?.takeIf {
        reading.endsWith("つき") && it.endsWith("付き") && it.length > 2 &&
            it[it.lastIndex - 1].let { last -> last in 'ァ'..'ヿ' || last in '一'..'龯' } &&
            leading != null && leading != it && leading.length <= it.length &&
            leading.startsWith(it.removeSuffix("付き")) && leading !in explicitlyPreferred &&
            it in stable
    }
    val withCompound = if (attachedSuffix != null) {
        listOf(attachedSuffix) + stable.filter { it != attachedSuffix }
    } else stable
    return preferSingleKanaReading(reading, withCompound, exactRegistration)
}

/** Complete model and standard conversions lead; personal results follow other complete readings. */
internal fun prioritizeJapaneseCandidateGroups(
    candidates: Iterable<String>,
    dictionaryCandidates: Iterable<String>,
    learnedCandidates: Iterable<String>,
    predictionTexts: Set<String> = emptySet(),
    fallbackTexts: Set<String> = emptySet(),
    partialTexts: Set<String> = emptySet(),
    preferredZenzaiCandidate: String? = null,
): List<String> = linkedSetOf<String>().apply {
    val dictionary = dictionaryCandidates.filter(String::isNotBlank)
    val learned = learnedCandidates.filter(String::isNotBlank)
    val other = candidates.filter(String::isNotBlank)
    if (preferredZenzaiCandidate != null && preferredZenzaiCandidate in other &&
        preferredZenzaiCandidate !in predictionTexts && preferredZenzaiCandidate !in fallbackTexts &&
        preferredZenzaiCandidate !in partialTexts) {
        add(preferredZenzaiCandidate)
    }
    addAll(other.filter {
        it !in predictionTexts && it !in fallbackTexts && it !in partialTexts &&
            it !in dictionary && it !in learned
    })
    addAll(dictionary.filter { it !in predictionTexts && it !in partialTexts })
    addAll(learned.filter { it !in predictionTexts && it !in partialTexts })
    addAll(other.filter { it in predictionTexts && it !in dictionary && it !in learned })
    addAll(other.filter { it in partialTexts && it !in predictionTexts })
    addAll(dictionary.filter { it in partialTexts && it !in predictionTexts })
    addAll(learned.filter { it in partialTexts && it !in predictionTexts })
    addAll(dictionary.filter { it in predictionTexts })
    addAll(learned.filter { it in predictionTexts })
    addAll(other.filter { it in fallbackTexts })
}.toList()

internal fun firstCompleteJapaneseCandidateIndex(
    candidates: List<String>,
    predictionReadings: Map<String, String>,
): Int = candidates.indexOfFirst { it !in predictionReadings }.coerceAtLeast(0)

internal fun prefixPredictionEntries(
    reading: String,
    entries: Iterable<Pair<String, List<String>>>,
    limit: Int,
): List<ReadingPrediction> {
    if (reading.isEmpty() || limit <= 0) return emptyList()
    val normalized = katakanaToHiragana(reading)
    return entries.asSequence()
        .map { (ruby, values) -> katakanaToHiragana(ruby) to values }
        .filter { (ruby, _) -> ruby.length > normalized.length && ruby.startsWith(normalized) }
        .sortedBy { (ruby, _) -> ruby.length }
        .flatMap { (ruby, values) -> values.asSequence().map { ReadingPrediction(ruby, it) } }
        .filter { it.text.isNotBlank() }
        .distinctBy { it.text }
        .take(limit)
        .toList()
}

internal fun prefixPredictionValues(
    reading: String,
    entries: Iterable<Pair<String, List<String>>>,
    limit: Int,
): List<String> = prefixPredictionEntries(reading, entries, limit).map { it.text }

/** Balance a user's importance setting against the amount left to type. */
internal fun rankUserPrefixPredictions(
    reading: String,
    entries: Iterable<ReadingPrediction>,
    limit: Int,
): List<ReadingPrediction> {
    if (reading.isEmpty() || limit <= 0) return emptyList()
    val normalized = katakanaToHiragana(reading)
    return entries.asSequence()
        .filter { it.text.isNotBlank() && it.reading.length > normalized.length && it.reading.startsWith(normalized) }
        .sortedWith(
            compareByDescending<ReadingPrediction> {
                it.importance.coerceIn(1, 5) * 20 - (it.reading.length - normalized.length).coerceAtMost(1000) * 4
            }.thenBy { it.reading.length },
        )
        .distinctBy { it.text }
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
    val exact = conversions.toSet()
    return buildList {
        addAll(conversions.take(insertion))
        addAll(predictions.filter { it !in exact })
        addAll(conversions.drop(insertion))
    }.distinct()
}

/** Recalls learned words before limiting completions, without auto-completing a longer reading. */
internal fun rankJapaneseCandidates(
    reading: String,
    conversions: List<String>,
    predictions: List<String>,
    learning: Map<String, Int> = emptyMap(),
    predictionLimit: Int = 32,
): List<String> {
    if (reading.isEmpty()) return emptyList()
    val normalized = katakanaToHiragana(reading)
    val exact = conversions.filter(String::isNotBlank).toMutableSet()
    val completions = predictions.filter(String::isNotBlank).toMutableSet()
    val exactScores = mutableMapOf<String, Int>()
    val predictionScores = mutableMapOf<String, Int>()
    val remaining = mutableMapOf<String, Int>()
    for (entry in learnedCandidates(learning)) {
        val ruby = entry.reading
        val word = entry.text
        val count = entry.score
        if (word.isBlank() || !ruby.startsWith(normalized)) continue
        if (ruby == normalized) {
            exact.add(word)
            exactScores[word] = maxOf(exactScores[word] ?: 0, count)
        } else {
            completions.add(word)
            predictionScores[word] = maxOf(predictionScores[word] ?: 0, count)
            remaining[word] = minOf(remaining[word] ?: Int.MAX_VALUE, ruby.length - normalized.length)
        }
    }
    val ranked = exact.sortedByDescending { exactScores[it] ?: 0 }
    val predicted = completions.filter { it !in exact }.sortedWith(
        compareByDescending<String> { predictionScores[it] ?: 0 }
            .thenBy { remaining[it] ?: Int.MAX_VALUE },
    ).take(predictionLimit.coerceAtLeast(0))
    return prioritizePrefixPredictions(ranked, predicted, insertIndex = 3)
}
