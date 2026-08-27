package io.github.StupidGame.azookey_flutter.conversion

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class JapaneseTextTransformsTest {
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
