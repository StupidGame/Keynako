package io.github.StupidGame.azookey_flutter.input

import kotlin.math.roundToInt

internal data class CenterCropRectangle(
    val left: Int,
    val top: Int,
    val width: Int,
    val height: Int,
)

/** Calculates a centered crop matching the keyboard's roughly 3:2 surface. */
internal fun centeredCropRectangle(
    sourceWidth: Int,
    sourceHeight: Int,
    targetAspectRatio: Double = 3.0 / 2.0,
): CenterCropRectangle {
    require(sourceWidth > 0 && sourceHeight > 0)
    require(targetAspectRatio > 0)
    val sourceAspectRatio = sourceWidth.toDouble() / sourceHeight
    return if (sourceAspectRatio > targetAspectRatio) {
        val width = (sourceHeight * targetAspectRatio).roundToInt().coerceIn(1, sourceWidth)
        CenterCropRectangle(
            left = (sourceWidth - width) / 2,
            top = 0,
            width = width,
            height = sourceHeight,
        )
    } else {
        val height = (sourceWidth / targetAspectRatio).roundToInt().coerceIn(1, sourceHeight)
        CenterCropRectangle(
            left = 0,
            top = (sourceHeight - height) / 2,
            width = sourceWidth,
            height = height,
        )
    }
}
