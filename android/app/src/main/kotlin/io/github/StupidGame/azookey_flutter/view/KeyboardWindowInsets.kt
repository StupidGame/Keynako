package io.github.StupidGame.azookey_flutter.view

import android.os.Build
import android.view.WindowInsets

internal data class KeyboardContentInsets(val left: Int, val right: Int, val bottom: Int)

/** Keep keys above home gestures even when the navigation hint is hidden. */
@Suppress("DEPRECATION")
internal fun keyboardContentInsets(insets: WindowInsets): KeyboardContentInsets {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val visible = insets.getInsets(
            WindowInsets.Type.navigationBars() or WindowInsets.Type.displayCutout() or
                WindowInsets.Type.tappableElement(),
        )
        val gestures = insets.getInsets(
            WindowInsets.Type.systemGestures() or WindowInsets.Type.mandatorySystemGestures(),
        )
        // The IME framework already excludes side back gestures. Only reserve
        // visible side obstructions; home gestures at the bottom remain active.
        return KeyboardContentInsets(visible.left, visible.right, maxOf(visible.bottom, gestures.bottom))
    }
    var left = insets.systemWindowInsetLeft
    var right = insets.systemWindowInsetRight
    var cutoutBottom = 0
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        insets.displayCutout?.let { cutout ->
            left = maxOf(left, cutout.safeInsetLeft)
            right = maxOf(right, cutout.safeInsetRight)
            cutoutBottom = cutout.safeInsetBottom
        }
    }
    val bottom = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        maxOf(
            insets.systemWindowInsetBottom,
            insets.systemGestureInsets.bottom,
            insets.mandatorySystemGestureInsets.bottom,
            insets.tappableElementInsets.bottom,
        )
    } else {
        insets.systemWindowInsetBottom
    }
    return KeyboardContentInsets(left, right, maxOf(bottom, cutoutBottom))
}
