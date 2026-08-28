package io.github.StupidGame.azookey_flutter.input

internal data class BackgroundImageOrientationTransform(
    val rotationDegrees: Int,
    val flipHorizontally: Boolean,
)

/** Converts all eight EXIF orientations into a horizontal flip followed by rotation. */
internal fun backgroundImageOrientationTransform(
    exifOrientation: Int,
): BackgroundImageOrientationTransform = when (exifOrientation) {
    2 -> BackgroundImageOrientationTransform(rotationDegrees = 0, flipHorizontally = true)
    3 -> BackgroundImageOrientationTransform(rotationDegrees = 180, flipHorizontally = false)
    4 -> BackgroundImageOrientationTransform(rotationDegrees = 180, flipHorizontally = true)
    5 -> BackgroundImageOrientationTransform(rotationDegrees = 270, flipHorizontally = true)
    6 -> BackgroundImageOrientationTransform(rotationDegrees = 90, flipHorizontally = false)
    7 -> BackgroundImageOrientationTransform(rotationDegrees = 90, flipHorizontally = true)
    8 -> BackgroundImageOrientationTransform(rotationDegrees = 270, flipHorizontally = false)
    else -> BackgroundImageOrientationTransform(rotationDegrees = 0, flipHorizontally = false)
}
