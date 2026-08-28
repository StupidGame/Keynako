package io.github.StupidGame.azookey_flutter.input

import org.junit.Assert.assertEquals
import org.junit.Test

class BackgroundImageOrientationTest {
    @Test
    fun mapsEveryExifOrientationToDisplayTransform() {
        val expected = listOf(
            BackgroundImageOrientationTransform(0, false),
            BackgroundImageOrientationTransform(0, true),
            BackgroundImageOrientationTransform(180, false),
            BackgroundImageOrientationTransform(180, true),
            BackgroundImageOrientationTransform(270, true),
            BackgroundImageOrientationTransform(90, false),
            BackgroundImageOrientationTransform(90, true),
            BackgroundImageOrientationTransform(270, false),
        )

        assertEquals(
            expected,
            (1..8).map(::backgroundImageOrientationTransform),
        )
    }

    @Test
    fun treatsMissingOrUnknownOrientationAsNormal() {
        val normal = BackgroundImageOrientationTransform(0, false)
        assertEquals(normal, backgroundImageOrientationTransform(0))
        assertEquals(normal, backgroundImageOrientationTransform(99))
    }
}
