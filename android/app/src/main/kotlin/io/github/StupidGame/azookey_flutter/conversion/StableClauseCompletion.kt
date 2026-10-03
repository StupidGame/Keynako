package io.github.StupidGame.azookey_flutter.conversion

data class CompletedClause(val reading: String, val text: String)

/** Waits for a converted first word to remain stable as the reading grows. */
class StableClauseCompletion {
    private var previousInput = ""
    private var previousClause: CompletedClause? = null
    private var stableCount = 0

    fun reset() {
        previousInput = ""
        previousClause = null
        stableCount = 0
    }

    fun observe(
        reading: String,
        candidate: String,
        entries: List<CompletedClause>,
        strength: Int,
        rawInput: String = reading,
    ): CompletedClause? {
        val threshold = when (strength) {
            1 -> 16
            2 -> 13
            3 -> 10
            4 -> 6
            else -> Int.MAX_VALUE
        }
        if (threshold == Int.MAX_VALUE || reading.isBlank() || candidate.isBlank()) {
            reset()
            return null
        }
        val clause = entries.asSequence().filter { entry ->
            entry.reading.length >= 2 && entry.reading.length < reading.length && entry.text.isNotBlank() &&
                reading.startsWith(entry.reading) && entry.text != entry.reading &&
                candidate.length > entry.text.length && candidate.startsWith(entry.text)
        }.maxWithOrNull(compareBy<CompletedClause> { it.reading.length }.thenBy { it.text.length })
        if (clause == null) {
            reset()
            return null
        }
        if (rawInput == previousInput) return null
        stableCount = if (rawInput.startsWith(previousInput) && clause == previousClause) stableCount + 1 else 1
        previousInput = rawInput
        previousClause = clause
        if (stableCount < threshold) return null
        reset()
        return clause
    }
}
