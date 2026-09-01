package io.github.StupidGame.azookey_flutter.view

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CustardLongPressTimingTest {
    @Test
    fun variationDurationOverridesParentDuration() {
        assertEquals(
            "light",
            custardVariationLongPressDuration(
                parentDuration = "normal",
                variationDuration = "light",
            ),
        )
    }

    @Test
    fun parentDurationIsUsedWhenVariationOmitsIt() {
        assertEquals(
            "normal",
            custardVariationLongPressDuration(
                parentDuration = "normal",
                variationDuration = "",
            ),
        )
    }

    @Test
    fun missingDurationsStayUnspecified() {
        assertNull(
            custardVariationLongPressDuration(
                parentDuration = null,
                variationDuration = null,
            ),
        )
    }
}
