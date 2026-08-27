package io.github.StupidGame.azookey_flutter.input

internal fun longPressDelayMillis(
    explicitDuration: String?,
    configuredDurationMs: Double,
): Long {
    if (explicitDuration == "light") return 125L
    return configuredDurationMs.coerceIn(150.0, 1000.0).toLong()
}
