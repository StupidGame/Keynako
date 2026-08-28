package io.github.StupidGame.azookey_flutter.input

import org.junit.Assert.assertEquals
import org.junit.Test

class KeyboardBackgroundCropTest {
    @Test
    fun cropsWideImagesAtTheHorizontalCenter() {
        assertEquals(
            CenterCropRectangle(left = 500, top = 0, width = 3000, height = 2000),
            centeredCropRectangle(sourceWidth = 4000, sourceHeight = 2000),
        )
    }

    @Test
    fun cropsTallImagesAtTheVerticalCenter() {
        assertEquals(
            CenterCropRectangle(left = 0, top = 1166, width = 1000, height = 667),
            centeredCropRectangle(sourceWidth = 1000, sourceHeight = 3000),
        )
    }
}
