package io.github.StupidGame.azookey_flutter.view

/**
 * Resolves the duration for a flick variation's own long-press action.
 *
 * Custard lets the parent key and each flick variation declare different
 * durations. Once a direction is selected, the variation controls the next
 * long-press timer; the parent is only a fallback for older definitions that
 * omit the variation duration.
 */
internal fun custardVariationLongPressDuration(
    parentDuration: String?,
    variationDuration: String?,
): String? = variationDuration
    ?.takeIf(String::isNotBlank)
    ?: parentDuration?.takeIf(String::isNotBlank)
