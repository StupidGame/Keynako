package io.github.StupidGame.azookey_flutter.conversion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class JapaneseTextTransformsTest {
    @Test
    fun pinsFullHiraganaAndKatakanaBeforeRankedCandidates() {
        assertEquals(
            listOf("きょう", "キョウ", "今日", "教", "京"),
            pinJapaneseKanaCandidates(
                reading = "キョウ",
                ranked = listOf("今日", "きょう", "教", "キョウ", "京"),
            ),
        )
    }

    @Test
    fun preservesTheExistingOrderAfterPinnedKanaCandidates() {
        assertEquals(
            listOf("にほんご", "ニホンゴ", "学習候補", "辞書候補", "Zenzai候補"),
            pinJapaneseKanaCandidates(
                reading = "にほんご",
                ranked = listOf("学習候補", "辞書候補", "Zenzai候補"),
            ),
        )
    }

    @Test
    fun prioritizesALiveConversionBeforePinnedKanaCandidates() {
        assertEquals(
            listOf("今日", "きょう", "キョウ", "教", "京"),
            pinJapaneseKanaCandidates(
                reading = "きょう",
                ranked = listOf("今日", "教", "京"),
                liveCandidate = "今日",
            ),
        )
    }

    @Test
    fun doesNotTreatRawKatakanaAsALiveConversion() {
        assertEquals(
            listOf("きょう", "キョウ", "今日"),
            pinJapaneseKanaCandidates(
                reading = "キョウ",
                ranked = listOf("キョウ", "今日"),
                liveCandidate = "キョウ",
            ),
        )
    }

    @Test
    fun commitsSymbolsAndSpacingWithoutConversion() {
        listOf("、", "。", "？", "！", "「」", "　", "\t", "😊", "＋").forEach { value ->
            assertTrue("$value should bypass conversion", shouldDirectCommitJapaneseInput(value))
        }
        val fullWidthSymbols = "！＂＃＄％＆＇（）＊＋，－．／：；＜＝＞？＠［＼］＾＿｀｛｜｝～￥"
        assertTrue(
            "full-width symbols should bypass conversion",
            shouldDirectCommitJapaneseInput(fullWidthSymbols),
        )
    }

    @Test
    fun commitsDecimalDigitsWithoutConversion() {
        listOf("123", "１２３", "٣٤٥").forEach { value ->
            assertTrue("$value should bypass conversion", shouldDirectCommitJapaneseInput(value))
            assertTrue(
                "$value from a Custard input action should bypass conversion",
                shouldDirectCommitJapaneseInput(
                    value,
                    JapaneseInputContext.CUSTARD_ACTION_SEQUENCE,
                ),
            )
        }
    }

    @Test
    fun keepsJapaneseReadingsInTheConversionPipeline() {
        listOf("きょう", "キョウ", "ー", "きょう？", "第3", "12a").forEach { value ->
            assertFalse("$value should remain convertible", shouldDirectCommitJapaneseInput(value))
        }
    }

    @Test
    fun keepsCustardSymbolMarkersInTheActionSequence() {
        listOf("・", "？", "＋").forEach { value ->
            assertFalse(
                "$value must remain available to a following replace_last_characters action",
                shouldDirectCommitJapaneseInput(
                    value,
                    JapaneseInputContext.CUSTARD_ACTION_SEQUENCE,
                ),
            )
        }
    }
}
