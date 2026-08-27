package io.github.StupidGame.azookey_flutter.input

import kotlin.math.abs

internal data class SurroundingDelete(
    val beforeCursor: Int = 0,
    val afterCursor: Int = 0,
)

/**
 * Custard's delete count is signed: positive values delete backward and
 * negative values delete forward.
 */
internal fun surroundingDeleteFor(count: Int): SurroundingDelete {
    val bounded = count.coerceIn(-100, 100)
    return when {
        bounded > 0 -> SurroundingDelete(beforeCursor = bounded)
        bounded < 0 -> SurroundingDelete(afterCursor = abs(bounded))
        else -> SurroundingDelete()
    }
}

/** Returns the amount of surrounding text removed by a Custard smart-delete. */
internal fun smartDeleteCount(
    text: String,
    targets: List<String>,
    backward: Boolean,
): Int {
    if (text.isEmpty()) return 0
    val distance = if (backward) {
        val boundary = targets.mapNotNull { target ->
            text.lastIndexOf(target).takeIf { it >= 0 }?.plus(target.length)
        }.maxOrNull() ?: 0
        text.length - boundary
    } else {
        targets.mapNotNull { target ->
            text.indexOf(target).takeIf { it >= 0 }
        }.minOrNull() ?: text.length
    }

    // azooKey also removes the boundary itself when the cursor is immediately
    // beside it, so a smart-delete never becomes a surprising no-op.
    return if (distance == 0) 1 else distance
}

internal enum class FiredLongPressTransition {
    CONTINUE,
    ROLLBACK_CENTER,
    KEEP_CENTER,
}

/** Decides whether a newly selected flick may replace an action that already fired. */
internal fun firedLongPressTransition(
    didLongPress: Boolean,
    variationDidLongPress: Boolean,
    canRollbackCenter: Boolean,
): FiredLongPressTransition = when {
    !didLongPress || variationDidLongPress -> FiredLongPressTransition.CONTINUE
    canRollbackCenter -> FiredLongPressTransition.ROLLBACK_CENTER
    else -> FiredLongPressTransition.KEEP_CENTER
}
