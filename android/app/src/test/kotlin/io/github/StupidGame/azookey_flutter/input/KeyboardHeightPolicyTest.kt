package io.github.StupidGame.azookey_flutter.input

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyboardHeightPolicyTest {
    @Test
    fun portraitRetainsTheExistingHeightsAndUserScale() {
        val normal = keyboardHeightMetrics(false, 890, 1f, 1.0)
        assertEquals(47, normal.rowHeight)
        assertEquals(43, normal.candidateBarHeight)
        assertEquals(176, normal.candidatePanelHeight)
        assertEquals(null, normal.maximumInputHeight)
        assertEquals(65, keyboardHeightMetrics(false, 890, 1f, 1.4).rowHeight)
    }

    @Test
    fun rotatingAPhoneSelectsCompactRowsAndCandidateBar() {
        val portrait = keyboardHeightMetrics(false, 890, 1f, 1.0)
        val landscape = keyboardHeightMetrics(true, 411, 1f, 1.0)
        assertEquals(36, landscape.rowHeight)
        assertEquals(32, landscape.candidateBarHeight)
        assertTrue(landscape.rowHeight < portrait.rowHeight)
        assertTrue(landscape.candidateBarHeight < portrait.candidateBarHeight)
        assertTrue(landscape.rowHeight * 4 + landscape.candidateBarHeight + 24 <= landscape.maximumInputHeight!!)
        assertEquals(portrait, keyboardHeightMetrics(false, 890, 1f, 1.0))
    }

    @Test
    fun maximumUserHeightAndExtraRowsKeepTheEditorVisibleAcrossDensities() {
        for (density in listOf(1f, 2.75f, 3.5f)) {
            for (heightDp in listOf(240, 320, 411, 600)) {
                for (scale in listOf(0.7, 1.0, 1.4)) {
                    for (rows in listOf(4, 5, 6, 40)) {
                        for (panel in listOf(false, true)) {
                            val height = (heightDp * density).toInt()
                            val metrics = keyboardHeightMetrics(true, height, density, scale)
                            val inset = (24 * density).toInt()
                            val body = metrics.maximumBodyHeight(inset, panel)!!
                            val natural = rows * metrics.rowHeight
                            val factor = keyboardBodyHeightScale(natural, body, metrics.rowHeight, metrics.minimumRowHeight)
                            val visibleBody = minOf((natural * factor).toInt(), body)
                            val total = inset + metrics.candidateBarHeight + visibleBody +
                                if (panel) metrics.candidatePanelHeight else 0
                            assertTrue("height=$heightDp density=$density scale=$scale rows=$rows panel=$panel", total <= height * 0.55)
                        }
                    }
                }
            }
        }
    }

    @Test
    fun openingCandidatesShrinksTheKeysAndClosingRestoresTheirPreferredHeight() {
        val metrics = keyboardHeightMetrics(true, 411, 1f, 1.4)
        val natural = metrics.rowHeight * 4
        val closed = keyboardBodyHeightScale(natural, metrics.maximumBodyHeight(24, false), metrics.rowHeight, 24)
        val opened = keyboardBodyHeightScale(natural, metrics.maximumBodyHeight(24, true), metrics.rowHeight, 24)
        assertTrue(opened < closed)
        assertTrue((natural * opened).toInt() <= metrics.maximumBodyHeight(24, true)!!)
        assertEquals(closed, keyboardBodyHeightScale(natural, metrics.maximumBodyHeight(24, false), metrics.rowHeight, 24), 0.0001)
    }

    @Test
    fun veryTallCustomLayoutsRetainReadableKeysAndUseTheBoundedViewport() {
        val metrics = keyboardHeightMetrics(true, 411, 1f, 1.0)
        val body = metrics.maximumBodyHeight(24, false)!!
        val natural = metrics.rowHeight * 40
        val factor = keyboardBodyHeightScale(natural, body, metrics.rowHeight, metrics.minimumRowHeight)
        assertTrue(metrics.rowHeight * factor >= 24)
        assertTrue(natural * factor > body)
    }

    @Test
    fun emptyAndPortraitBodiesNeverDivideOrShrink() {
        assertEquals(1.0, keyboardBodyHeightScale(0, 100, 36, 24), 0.0)
        assertEquals(1.0, keyboardBodyHeightScale(1000, null, 47, 32), 0.0)
    }
}
