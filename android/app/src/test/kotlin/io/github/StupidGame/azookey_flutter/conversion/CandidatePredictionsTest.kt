package io.github.StupidGame.azookey_flutter.conversion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CandidatePredictionsTest {
    @Test
    fun commitsTheRawReadingWhenCandidateConversionIsDisabled() {
        assertEquals(
            "かめん",
            compositionCommitText(
                reading = "かめん",
                candidates = listOf("仮面", "画面"),
                useCandidate = false,
            ),
        )
        assertEquals(
            "仮面",
            compositionCommitText(
                reading = "かめん",
                candidates = listOf("仮面", "画面"),
                useCandidate = true,
            ),
        )
    }

    @Test
    fun givesImportantUserWordsMoreDictionaryWeight() {
        assertEquals(-13.0, userDictionaryWordWeight(1), 0.0)
        assertEquals(-5.0, userDictionaryWordWeight(5), 0.0)
    }

    @Test
    fun dynamicDictionaryCacheVersionTracksEveryCandidate() {
        val first = AzooKeyHotfixDictionaryEntry("Key", "きー", -5.0, 1285, 1285, 501)
        val second = first.copy(word = "キー")

        assertEquals(
            additionalDictionaryVersion("base", listOf(first)),
            additionalDictionaryVersion("base", listOf(first)),
        )
        assertNotEquals(
            additionalDictionaryVersion("base", listOf(first)),
            additionalDictionaryVersion("base", listOf(second)),
        )
    }

    @Test
    fun englishPredictionsKeepTypedTextFirstAndCompleteItsPrefix() {
        assertEquals(
            listOf("hel", "hello", "help"),
            englishPredictionCandidates("hel"),
        )
    }

    @Test
    fun englishPredictionsPreserveTheTypedCapitalization() {
        assertEquals(
            listOf("Hel", "Hello", "Help"),
            englishPredictionCandidates("Hel"),
        )
        assertEquals(
            listOf("HEL", "HELLO", "HELP"),
            englishPredictionCandidates("HEL"),
        )
    }

    @Test
    fun caseFormsKeepCustomLayoutTextAvailableForContinuedConversion() {
        assertEquals("HEL", caseConvertedComposition("Hel", "uppercase"))
        assertEquals("hello", caseConvertedComposition("Hello", "lowercase"))
        assertEquals(
            listOf("HEL", "HELLO", "HELP"),
            englishPredictionCandidates(
                checkNotNull(caseConvertedComposition("hel", "uppercase")),
            ),
        )
        assertNull(caseConvertedComposition("かな", "katakana"))
    }

    @Test
    fun returnsWordsWhoseReadingStartsWithThePartialInput() {
        val values = prefixPredictionValues(
            reading = "かめん",
            entries = listOf(
                "かめん" to listOf("仮面"),
                "かめんらいだー" to listOf("仮面ライダー"),
                "かみなり" to listOf("雷"),
            ),
            limit = 8,
        )

        assertEquals(listOf("仮面ライダー"), values)
    }

    @Test
    fun placesPredictionsAfterTheLeadingConversionCandidates() {
        val values = prioritizePrefixPredictions(
            conversions = listOf("仮面", "画面", "かめん"),
            predictions = listOf("仮面ライダー"),
        )

        assertEquals(listOf("仮面", "画面", "仮面ライダー", "かめん"), values)
    }
}
