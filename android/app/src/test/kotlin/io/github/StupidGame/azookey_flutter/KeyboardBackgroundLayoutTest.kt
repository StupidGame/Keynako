package io.github.StupidGame.azookey_flutter

import org.junit.Assert.assertEquals
import org.junit.Test

class KeyboardBackgroundLayoutTest {
    @Test
    fun centerCropsAWideImage() {
        assertEquals(
            BackgroundImageDestination(-100f, 0f, 300f, 200f),
            centerCropDestination(
                containerWidth = 200,
                containerHeight = 200,
                imageWidth = 400,
                imageHeight = 200,
            ),
        )
    }

    @Test
    fun centerCropsATallImage() {
        assertEquals(
            BackgroundImageDestination(0f, -100f, 200f, 300f),
            centerCropDestination(
                containerWidth = 200,
                containerHeight = 200,
                imageWidth = 200,
                imageHeight = 400,
            ),
        )
    }

    @Test
    fun skipsCenterCropUntilTheFrameHasASize() {
        assertEquals(
            null,
            centerCropDestination(
                containerWidth = 200,
                containerHeight = 0,
                imageWidth = 400,
                imageHeight = 200,
            ),
        )
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
