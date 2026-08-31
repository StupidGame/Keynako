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

/**
 * Resolves Custard's common `delete` + backward smart-delete sequence in one
 * pass. Keeping the pair atomic avoids reading stale surrounding text between
 * the two editor operations, which is especially visible with Japanese IMEs.
 */
internal fun combinedBackwardSmartDeleteCount(
    text: String,
    leadingDeleteCount: Int,
    targets: List<String>,
): Int {
    if (text.isEmpty()) return 0
    val leading = leadingDeleteCount.coerceAtLeast(0).coerceAtMost(text.length)
    val remaining = text.dropLast(leading)
    if (remaining.isEmpty()) return leading
    return (leading + smartDeleteCount(remaining, targets, backward = true))
        .coerceAtMost(text.length)
}

internal data class CustardDeleteContinuationAction(
    val type: String,
    val count: Int = 1,
    val direction: String = "",
)

/**
 * Returns where a backward smart-delete should resume after the center key's
 * long-press delete has already fired.
 */
internal fun backwardSmartDeleteContinuationStartIndex(
    actions: List<CustardDeleteContinuationAction>,
): Int? {
    fun CustardDeleteContinuationAction.isBackwardSmartDelete(): Boolean =
        type == "smart_delete_default" ||
            (type == "smart_delete" && direction == "backward")

    if (
        actions.firstOrNull()?.isBackwardSmartDelete() == true
    ) {
        return 0
    }
    return if (
        actions.firstOrNull()?.let { it.type == "delete" && it.count > 0 } == true &&
        actions.getOrNull(1)?.isBackwardSmartDelete() == true
    ) {
        1
    } else {
        null
    }
}

internal data class LastCharactersReplacement(
    val removedLength: Int,
    val replacement: String,
) {
    fun applyTo(text: String): String = text.dropLast(removedLength) + replacement
}

/**
 * Finds the longest matching Custard suffix. Character-form tables also fall
 * back to the shared kana cycle when their marker table omits the final form.
 */
internal fun lastCharactersReplacementIn(
    text: String,
    table: Map<String, String>,
): LastCharactersReplacement? {
    val match = table.keys.filter(text::endsWith).maxByOrNull(String::length)
    if (match != null) {
        return LastCharactersReplacement(match.length, table.getValue(match))
    }

    val formEntries = table.entries.mapNotNull { (source, replacement) ->
        if (source.length != 2 || replacement.length != 1) return@mapNotNull null
        val character = source.take(1)
        val suffix = source.takeLast(1)
        Triple(character, suffix, replacement)
            .takeIf { sharesKanaCharacterFormCycle(character, replacement) }
    }
    for (marker in formEntries.map { it.second }.distinct()) {
        if (!text.endsWith(marker)) continue
        val sourceWithoutMarker = text.dropLast(marker.length)
        val last = sourceWithoutMarker.takeLast(1)
        val participatesInTable = formEntries.any { (source, suffix, replacement) ->
            suffix == marker && (last == source || last == replacement)
        }
        if (!participatesInTable) continue
        val replacement = kanaCharacterFormReplacement(last) ?: continue
        return LastCharactersReplacement(last.length + marker.length, replacement)
    }
    return null
}

/** Applies a Custard suffix replacement without discarding the word prefix. */
internal fun replaceLastCharactersIn(
    text: String,
    table: Map<String, String>,
): String = lastCharactersReplacementIn(text, table)?.applyTo(text) ?: text

internal enum class FiredLongPressTransition {
    CONTINUE,
    ROLLBACK_CENTER,
    CONTINUE_AFTER_CENTER_DELETE,
    KEEP_CENTER,
}

/** Decides whether a newly selected flick may replace an action that already fired. */
internal fun firedLongPressTransition(
    didLongPress: Boolean,
    variationDidLongPress: Boolean,
    canRollbackCenter: Boolean,
    canContinueAfterCenterDelete: Boolean = false,
): FiredLongPressTransition = when {
    !didLongPress || variationDidLongPress -> FiredLongPressTransition.CONTINUE
    canRollbackCenter -> FiredLongPressTransition.ROLLBACK_CENTER
    canContinueAfterCenterDelete -> FiredLongPressTransition.CONTINUE_AFTER_CENTER_DELETE
    else -> FiredLongPressTransition.KEEP_CENTER
}
