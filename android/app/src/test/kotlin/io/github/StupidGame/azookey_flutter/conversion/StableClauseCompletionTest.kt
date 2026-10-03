package io.github.StupidGame.azookey_flutter.conversion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StableClauseCompletionTest {
    @Test fun completesOnlyAfterTheConfiguredNumberOfStableUpdates() {
        val completion = StableClauseCompletion()
        val entries = listOf(CompletedClause("わたし", "私"))
        for (reading in listOf("わたしは", "わたしはね", "わたしはねこ", "わたしはねこで", "わたしはねこです")) {
            assertNull(completion.observe(reading, "私は猫です", entries, 4))
        }
        assertEquals(CompletedClause("わたし", "私"), completion.observe("わたしはねこですか", "私は猫ですか", entries, 4))
    }

    @Test fun resetsOnCandidateChangeAndDoesNotCompleteWhenDisabled() {
        val completion = StableClauseCompletion()
        val entries = listOf(CompletedClause("わたし", "私"))
        assertNull(completion.observe("わたしは", "私は", entries, 4))
        assertNull(completion.observe("わたしはね", "別の候補", entries, 4))
        assertNull(completion.observe("わたしはねこ", "私は猫", entries, 0))
    }

    @Test fun neverCompletesAnEmptyDictionaryWord() {
        val completion = StableClauseCompletion()
        val entries = listOf(CompletedClause("わたし", ""))
        for (reading in listOf("わたしは", "わたしはね", "わたしはねこ", "わたしはねこで", "わたしはねこです", "わたしはねこですか")) {
            assertNull(completion.observe(reading, "私は猫ですか", entries, 4))
        }
    }

    @Test fun romanInputCanRewriteItsUnfinishedSuffix() {
        val completion = StableClauseCompletion()
        val entries = listOf(CompletedClause("わたし", "私"))
        val input = listOf(
            "わたしはk" to "watashihak",
            "わたしはky" to "watashihaky",
            "わたしはきょ" to "watashihakyo",
            "わたしはきょう" to "watashihakyou",
            "わたしはきょうt" to "watashihakyout",
            "わたしはきょうと" to "watashihakyouto",
        )
        for ((reading, raw) in input.dropLast(1)) {
            assertNull(completion.observe(reading, "私は今日", entries, 4, raw))
        }
        val (reading, raw) = input.last()
        assertEquals(CompletedClause("わたし", "私"), completion.observe(reading, "私は今日", entries, 4, raw))
    }
}
