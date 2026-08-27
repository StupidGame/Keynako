package io.github.StupidGame.azookey_flutter.input

internal fun longPressDelayMillis(
    explicitDuration: String?,
    configuredDurationMs: Double,
): Long {
    if (explicitDuration == "light") return 125L
    return configuredDurationMs.coerceIn(150.0, 1000.0).toLong()
}

/**
 * Keeps the flick variation that owns a pending long-press gesture selected.
 *
 * A finger can briefly move back inside the flick threshold while it is held.
 * That jitter must not switch the pending long press back to the center key.
 */
internal class FlickLongPressSelection<T>(private val center: T) {
    var direction: String? = null
        private set

    var target: T? = center
        private set

    fun reset() {
        direction = null
        target = center
    }

    fun update(detectedDirection: String?, resolve: (String) -> T?): Boolean {
        if (detectedDirection == null || detectedDirection == direction) return false
        direction = detectedDirection
        target = resolve(detectedDirection)
        return true
    }
}
