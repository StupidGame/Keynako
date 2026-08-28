package io.github.StupidGame.azookey_flutter

import org.junit.Assert.assertEquals
import org.junit.Test

class KeyboardBackgroundLayoutTest {
    @Test
    fun ignoresImageSizeWhileParentIsMeasuringKeyboardContent() {
        assertEquals(0, decorativeImageMeasuredDimension(isExact = false, exactSize = 4000))
    }

    @Test
    fun fillsKeyboardAfterParentSizeIsFixed() {
        assertEquals(258, decorativeImageMeasuredDimension(isExact = true, exactSize = 258))
    }
}
