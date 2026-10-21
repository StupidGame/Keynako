package io.github.StupidGame.azookey_flutter.conversion

/** Retains a converted prefix while the dictionary catches up with continued typing. */
internal class LiveConversionPreview {
    var session: Long = 0
        private set
    private var currentReading = ""
    private var currentInput = ""
    private var convertedReading = ""
    private var convertedText = ""

    fun reset() {
        session++
        currentReading = ""
        currentInput = ""
        convertedReading = ""
        convertedText = ""
    }

    fun updateReading(reading: String, rawInput: String = reading) {
        if (reading.isEmpty() || !rawInput.startsWith(currentInput)) reset()
        currentReading = reading
        currentInput = rawInput
        // Adding a Roman key can replace an unfinished syllable (k -> か,
        // ん -> な). Keep the earlier conversion only if its reading still fits.
        if (!reading.startsWith(convertedReading)) {
            convertedReading = ""
            convertedText = ""
        }
    }

    fun remember(requestSession: Long, reading: String, text: String): Boolean {
        if (requestSession != session || reading.isEmpty() || text.isBlank() ||
            !currentReading.startsWith(reading) || reading.length < convertedReading.length) return false
        convertedReading = reading
        convertedText = text
        return true
    }

    fun preview(reading: String): String? {
        if (reading != currentReading || convertedReading.isEmpty() ||
            !reading.startsWith(convertedReading)) return null
        return convertedText + reading.substring(convertedReading.length)
    }
}

/** A temporary prefix must not replace a complete local conversion or a registration. */
internal fun pendingLiveConversionCandidates(
    reading: String,
    candidates: List<String>,
    preview: String?,
    predictionTexts: Set<String>,
    partialTexts: Set<String>,
    exactRegistrationTexts: Set<String> = emptySet(),
): List<String> {
    if (preview.isNullOrBlank() || preview == reading) return candidates
    val leading = candidates.firstOrNull { it !in predictionTexts }
    if (leading in exactRegistrationTexts) return candidates
    if (leading != null && leading !in japaneseReadingForms(reading) &&
        leading !in partialTexts) return candidates
    return listOf(preview) + candidates.filter { it != preview }
}
