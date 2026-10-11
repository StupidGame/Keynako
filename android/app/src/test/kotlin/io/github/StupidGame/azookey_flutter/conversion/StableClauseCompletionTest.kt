package io.github.StupidGame.azookey_flutter.conversion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StableClauseCompletionTest {
    @Test fun completesOnlyAfterTheConfiguredNumberOfStableUpdates() {
        val completion = StableClauseCompletion()
        val entries = listOf(CompletedClause("わたし", "私"))
        val first = "わたしはきょうとうきょうのえきで"
        for (reading in listOf(first, "$firstと", "$firstとも", "$firstともだ", "$firstともだち")) {
            assertNull(completion.observe(reading, "私は今日東京の駅で友達", entries, 4))
        }
        assertEquals(CompletedClause("わたし", "私"), completion.observe(
            "$firstともだちと", "私は今日東京の駅で友達と", entries, 4,
        ))
    }

    @Test fun resetsOnCandidateChangeAndDoesNotCompleteWhenDisabled() {
        val completion = StableClauseCompletion()
        val entries = listOf(CompletedClause("わたし", "私"))
        val first = "わたしはきょうとうきょうのえきで"
        assertNull(completion.observe(first, "私は今日東京の駅で", entries, 4))
        assertNull(completion.observe("$firstと", "別の候補", entries, 4))
        assertNull(completion.observe("$firstとも", "私は今日東京の駅で友", entries, 0))
    }

    @Test fun neverCompletesAnEmptyDictionaryWord() {
        val completion = StableClauseCompletion()
        val entries = listOf(CompletedClause("わたし", ""))
        val first = "わたしはきょうとうきょうのえきで"
        for (reading in listOf(first, "$firstと", "$firstとも", "$firstともだ", "$firstともだち", "$firstともだちと")) {
            assertNull(completion.observe(reading, "私は今日東京の駅で友達と", entries, 4))
        }
    }

    @Test fun shortPhraseNeverCommitsWhileRomanInputIsStillBeingTyped() {
        val completion = StableClauseCompletion()
        val entries = listOf(CompletedClause("ほんらい", "本来"))
        val input = "honrainomokuteki"
        for (length in 1..input.length) {
            val raw = input.take(length)
            assertNull(completion.observe(romanToHiragana(raw), "本来の目的", entries, 4, raw))
        }
    }
}
