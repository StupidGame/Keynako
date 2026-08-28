package io.github.StupidGame.azookey_flutter.input

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LongPressTimingTest {
    @Test
    fun lightFlickVariationOverridesNormalCenterTiming() {
        val centerDelay = longPressDelayMillis("normal", configuredDurationMs = 400.0)
        val variationDelay = longPressDelayMillis("light", configuredDurationMs = 400.0)

        assertEquals(400L, centerDelay)
        assertEquals(125L, variationDelay)
    }

    @Test
    fun normalDurationUsesTheConfiguredTimingWithinSupportedBounds() {
        assertEquals(400L, longPressDelayMillis("normal", configuredDurationMs = 400.0))
        assertEquals(150L, longPressDelayMillis(null, configuredDurationMs = 100.0))
        assertEquals(1_000L, longPressDelayMillis("normal", configuredDurationMs = 1_500.0))
    }

    @Test
    fun selectedTopVariationUsesCustardDirectionAndSurvivesNeutralJitter() {
        val selection = FlickLongPressSelection(center = listOf("し"))
        val largeYaActions = listOf("ゃ", "しゃ→しや")
        val variations = mapOf("top" to largeYaActions)

        assertTrue(selection.update("up") { variations[custardFlickDirection(it)] })
        assertFalse(selection.update(null) { error("a neutral jitter must keep the selected variation") })

        assertEquals("up", selection.direction)
        assertEquals(largeYaActions, selection.target)
    }

    @Test
    fun mapsAndroidVerticalDirectionsToCustardNames() {
        assertEquals("top", custardFlickDirection("up"))
        assertEquals("bottom", custardFlickDirection("down"))
        assertEquals("left", custardFlickDirection("left"))
        assertEquals("right", custardFlickDirection("right"))
        assertEquals(null, custardFlickDirection(null))
    }
}
