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

    @Test
    fun reloadsImageWhenInputViewWasRecreatedWithTheSameSignature() {
        assertEquals(
            true,
            shouldReloadKeyboardBackground(
                signature = "theme.image:1",
                loadedSignature = "theme.image:1",
                hasDrawable = false,
            ),
        )
    }

    @Test
    fun keepsAnExistingImageWhenNothingChanged() {
        assertEquals(
            false,
            shouldReloadKeyboardBackground(
                signature = "theme.image:1",
                loadedSignature = "theme.image:1",
                hasDrawable = true,
            ),
        )
    }
}
