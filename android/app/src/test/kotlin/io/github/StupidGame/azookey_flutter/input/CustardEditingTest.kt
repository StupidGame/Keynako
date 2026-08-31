package io.github.StupidGame.azookey_flutter.input

import org.junit.Assert.assertEquals
import org.junit.Test

class CustardEditingTest {
    @Test
    fun signedDeleteCountPreservesForwardDelete() {
        assertEquals(SurroundingDelete(beforeCursor = 2), surroundingDeleteFor(2))
        assertEquals(SurroundingDelete(afterCursor = 1), surroundingDeleteFor(-1))
        assertEquals(SurroundingDelete(), surroundingDeleteFor(0))
    }

    @Test
    fun custardWordDeleteRemovesTheRestOfTheCurrentToken() {
        // The layout first deletes the final character, then smart-deletes back
        // to the nearest separator.
        val afterFirstDelete = "前の単語 かな配"
        val count = smartDeleteCount(afterFirstDelete, listOf(" ", "。", "、"), backward = true)

        assertEquals("かな配".length, count)
        assertEquals("前の単語 ", afterFirstDelete.dropLast(count))
    }

    @Test
    fun smartDeleteConsumesAnAdjacentBoundaryInsteadOfDoingNothing() {
        assertEquals(1, smartDeleteCount("一語 ", listOf(" "), backward = true))
        assertEquals(1, smartDeleteCount(" 次", listOf(" "), backward = false))
    }

    @Test
    fun chainedDeleteAndSmartDeleteRemoveJapaneseTextAtomically() {
        assertEquals(
            3,
            combinedBackwardSmartDeleteCount("前。次の文", 1, listOf("。")),
        )
        assertEquals(
            5,
            combinedBackwardSmartDeleteCount("日本語入力", 1, listOf("。", "、")),
        )
    }

    @Test
    fun japaneseWordDeleteContinuesAfterTheCenterLongPressDelete() {
        val smartDelete = CustardDeleteContinuationAction(
            type = "smart_delete",
            direction = "backward",
        )
        assertEquals(
            0,
            backwardSmartDeleteContinuationStartIndex(listOf(smartDelete)),
        )
        assertEquals(
            0,
            backwardSmartDeleteContinuationStartIndex(
                listOf(CustardDeleteContinuationAction(type = "smart_delete_default")),
            ),
        )
        assertEquals(
            1,
            backwardSmartDeleteContinuationStartIndex(
                listOf(CustardDeleteContinuationAction(type = "delete"), smartDelete),
            ),
        )
        assertEquals(
            1,
            backwardSmartDeleteContinuationStartIndex(
                listOf(
                    CustardDeleteContinuationAction(type = "delete"),
                    CustardDeleteContinuationAction(type = "smart_delete_default"),
                ),
            ),
        )
        assertEquals(
            null,
            backwardSmartDeleteContinuationStartIndex(
                listOf(smartDelete.copy(direction = "forward")),
            ),
        )
    }

    @Test
    fun custardReplacementKeepsTheWholeWordAndUsesTheLongestSuffix() {
        val result = replaceLastCharactersIn(
            "前のことばしよ",
            mapOf("よ" to "ょ", "しよ" to "しょ"),
        )

        assertEquals("前のことばしょ", result)
    }

    @Test
    fun customDakutenTableCompletesEverySemiVoicedKanaCycle() {
        val wordTable = mapOf("お願い・" to "お願いいたします")
        val table = mapOf(
            "は・" to "ば", "ば・" to "ぱ",
            "ひ・" to "び", "び・" to "ぴ",
            "ふ・" to "ぶ", "ぶ・" to "ぷ",
            "へ・" to "べ", "べ・" to "ぺ",
            "ほ・" to "ぼ", "ぼ・" to "ぽ",
            "わ・" to "ゎ",
            "・・" to "w",
        )

        listOf(
            listOf("は", "ば", "ぱ", "は", "ば"),
            listOf("ひ", "び", "ぴ", "ひ", "び"),
            listOf("ふ", "ぶ", "ぷ", "ふ", "ぶ"),
            listOf("へ", "べ", "ぺ", "へ", "べ"),
            listOf("ほ", "ぼ", "ぽ", "ほ", "ぼ"),
            listOf("わ", "ゎ", "わ", "ゎ", "わ"),
        ).forEach { expected ->
            val actual = buildList {
                var value = expected.first()
                add(value)
                repeat(expected.lastIndex) {
                    value = replaceLastCharactersIn("$value・", wordTable)
                    value = replaceLastCharactersIn(value, table)
                    add(value)
                }
            }
            assertEquals(expected, actual)
        }
    }

    @Test
    fun ordinarySuffixTablesDoNotEnableKanaCycling() {
        assertEquals(
            "は・",
            replaceLastCharactersIn(
                "は・",
                mapOf("お願い・" to "お願いいたします"),
            ),
        )
        assertEquals(
            "か・",
            replaceLastCharactersIn("か・", mapOf("は・" to "ば", "ば・" to "ぱ")),
        )
    }

    @Test
    fun lateCustardFlickRollsBackTheCenterAction() {
        assertEquals(
            FiredLongPressTransition.ROLLBACK_CENTER,
            firedLongPressTransition(
                didLongPress = true,
                variationDidLongPress = false,
                canRollbackCenter = true,
            ),
        )
        assertEquals(
            FiredLongPressTransition.KEEP_CENTER,
            firedLongPressTransition(
                didLongPress = true,
                variationDidLongPress = false,
                canRollbackCenter = false,
            ),
        )
    }

    @Test
    fun wordDeleteContinuesWhenTheCenterDeleteAlreadyFired() {
        assertEquals(
            FiredLongPressTransition.CONTINUE_AFTER_CENTER_DELETE,
            firedLongPressTransition(
                didLongPress = true,
                variationDidLongPress = false,
                canRollbackCenter = false,
                canContinueAfterCenterDelete = true,
            ),
        )
    }
}
