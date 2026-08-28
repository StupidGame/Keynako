package io.github.StupidGame.azookey_flutter.conversion

import org.junit.Assert.assertEquals
import org.junit.Test

class CandidatePredictionsTest {
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
