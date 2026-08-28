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
    fun oguraWordDeleteRemovesTheRestOfTheCurrentToken() {
        // The layout first deletes the final character, then smart-deletes back
        // to the nearest separator.
        val afterFirstDelete = "前の単語 おぐら配"
        val count = smartDeleteCount(afterFirstDelete, listOf(" ", "。", "、"), backward = true)

        assertEquals("おぐら配".length, count)
        assertEquals("前の単語 ", afterFirstDelete.dropLast(count))
    }

    @Test
    fun smartDeleteConsumesAnAdjacentBoundaryInsteadOfDoingNothing() {
        assertEquals(1, smartDeleteCount("一語 ", listOf(" "), backward = true))
        assertEquals(1, smartDeleteCount(" 次", listOf(" "), backward = false))
    }

    @Test
    fun oguraReplacementKeepsTheWholeWordAndUsesTheLongestSuffix() {
        val result = replaceLastCharactersIn(
            "前のおぐらしよ",
            mapOf("よ" to "ょ", "しよ" to "しょ"),
        )

        assertEquals("前のおぐらしょ", result)
    }

    @Test
    fun lateOguraFlickRollsBackTheCenterPeriodBeforeSmallE() {
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
    fun oguraWordDeleteContinuesWhenTheCenterDeleteAlreadyFired() {
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
