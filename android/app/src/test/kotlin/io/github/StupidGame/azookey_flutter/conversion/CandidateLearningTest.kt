package io.github.StupidGame.azookey_flutter.conversion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CandidateLearningTest {
    @Test
    fun correctionOvertakesPreviouslyFrequentChoice() {
        val learning = mutableMapOf("あい\t愛" to 1_000_000, "べつ\t別" to 7)
        recordCandidateLearning(learning, "あい", "藍", explicitSelection = true)
        assertTrue(learning.getValue("あい\t藍") > learning.getValue("あい\t愛"))
        assertEquals(7, learning["べつ\t別"])
        assertEquals("藍", rankJapaneseCandidates("あい", listOf("愛", "藍"), emptyList(), learning).first())
        assertEquals("藍", prioritizeLearnedJapaneseCandidates("あい", listOf("愛", "藍"), learning).first())
    }

    @Test
    fun repeatedSelectionsStrengthenPreferenceWithABoundedScore() {
        val learning = mutableMapOf<String, Int>()
        repeat(100) {
            val previous = learning["あい\t藍"] ?: 0
            recordCandidateLearning(learning, "あい", "藍", explicitSelection = true)
            assertTrue(learning.getValue("あい\t藍") in previous..32)
        }
        recordCandidateLearning(learning, "あい", "愛", explicitSelection = true)
        assertTrue(learning.getValue("あい\t愛") > learning.getValue("あい\t藍"))
    }

    @Test
    fun kanaVariantsMergeWithoutChangingOtherLanguageScores() {
        val learning = mutableMapOf("アイ\t愛" to 9, "あい\t愛" to 5, "english:ai\tAI" to 6)
        recordCandidateLearning(learning, "アイ", "藍", explicitSelection = true)
        assertTrue("アイ\t愛" !in learning)
        assertEquals(4, learning["あい\t愛"])
        assertEquals(6, learning["english:ai\tAI"])
    }

    @Test
    fun legacyEnglishScoresAreMigratedWithoutLeakingJapaneseLearning() {
        val learning = mutableMapOf("Hel\tHello" to 10, "english:hel\thello" to 7, "はろー\thelloworld" to 30)
        recordCandidateLearning(learning, "HEL", "HELLO", english = true, explicitSelection = true)
        assertEquals(14, learning["english:hel\tHELLO"])
        assertTrue("Hel\tHello" !in learning)
        assertTrue("english:hel\thello" !in learning)
        val values = englishPredictionCandidates("Hel", learning = learning)
        assertEquals(listOf("HELLO", "Hel"), values.take(2))
        assertTrue("Helloworld" !in values)
    }

    @Test
    fun englishLearningWorksForLongerPrefixesWithoutAutoCompletion() {
        val learning = mapOf("english:he\thelium" to 8)
        assertEquals(listOf("helium", "heli"), englishPredictionCandidates("heli", learning = learning))
        assertEquals(listOf("heli"), englishPredictionCandidates("heli"))
    }

    @Test
    fun commitUsesTheSelectedCandidateInsteadOfLearningTheFirstOne() {
        assertEquals("藍", compositionCommitText("あい", listOf("愛", "藍"), true, selectedIndex = 1))
        assertEquals("あい", compositionCommitText("あい", listOf("愛", "藍"), false, selectedIndex = 1))
    }
}
