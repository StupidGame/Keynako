package io.github.StupidGame.azookey_flutter.input

import java.text.BreakIterator
import java.util.Locale
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
 * Returns the UTF-16 length of exactly one word (or one trailing punctuation
 * cluster) immediately before the cursor. The platform iterator handles most
 * Japanese text; [refinedJapaneseWordStart] supplies the boundaries that are
 * commonly missing from an all-kana phrase.
 */
internal fun backwardWordDeleteCount(
    text: String,
    locale: Locale = Locale.JAPANESE,
): Int {
    if (text.isEmpty()) return 0

    var contentEnd = text.length
    while (contentEnd > 0) {
        val codePoint = Character.codePointBefore(text, contentEnd)
        if (!Character.isWhitespace(codePoint)) break
        contentEnd -= Character.charCount(codePoint)
    }
    if (contentEnd == 0) return text.length

    val iterator = BreakIterator.getWordInstance(locale).apply {
        setText(text.substring(0, contentEnd))
    }
    var start = iterator.first()
    var lastWordStart = -1
    var lastWordEnd = -1
    var end = iterator.next()
    while (end != BreakIterator.DONE) {
        if (containsWordCharacter(text, start, end)) {
            lastWordStart = start
            lastWordEnd = end
        }
        start = end
        end = iterator.next()
    }

    if (lastWordEnd == contentEnd) {
        return text.length - refinedJapaneseWordStart(text, lastWordStart, lastWordEnd)
    }
    if (lastWordEnd >= 0) return text.length - lastWordEnd

    val characters = BreakIterator.getCharacterInstance(locale).apply { setText(text) }
    val previous = characters.preceding(contentEnd).takeIf { it != BreakIterator.DONE } ?: 0
    return text.length - previous
}

private enum class JapaneseCharacterClass {
    HIRAGANA,
    KATAKANA,
    HAN,
    LATIN,
    DIGIT,
    OTHER,
}

private val japaneseParticles = listOf(
    "から", "まで", "より", "ので", "のに", "では", "には", "とは", "って",
    "を", "が", "は", "も", "の", "に", "へ", "で", "と", "や",
)

private val japaneseAuxiliaries = listOf(
    "ませんでした", "ましょう", "ました", "ません", "ます",
    "でした", "でしょう", "です", "だった", "だろう", "ない", "たい",
)

private val indivisibleKanaWords = setOf(
    "こんにちは", "こんばんは", "ありがとう", "おはよう",
)

/** Refines one platform word without ever extending its deletion range. */
private fun refinedJapaneseWordStart(text: String, start: Int, end: Int): Int {
    if (start >= end) return start

    val finalClass = japaneseCharacterClass(Character.codePointBefore(text, end))
    var runStart = end
    var cursor = end
    while (cursor > start) {
        val codePoint = Character.codePointBefore(text, cursor)
        if (japaneseCharacterClass(codePoint) != finalClass) break
        cursor -= Character.charCount(codePoint)
        runStart = cursor
    }

    // A script change is a stable boundary even when a platform iterator has
    // returned a mixed Japanese/Latin token as one word.
    if (runStart > start) return refineKanaGrammarBoundary(text, runStart, end)
    return refineKanaGrammarBoundary(text, start, end)
}

private fun refineKanaGrammarBoundary(text: String, start: Int, end: Int): Int {
    if (start >= end) return start
    val segment = text.substring(start, end)
    if (
        segment in indivisibleKanaWords ||
        segment.codePoints().anyMatch { japaneseCharacterClass(it) != JapaneseCharacterClass.HIRAGANA }
    ) {
        return start
    }

    japaneseAuxiliaries.firstOrNull { segment.length > it.length && segment.endsWith(it) }
        ?.let { return end - it.length }
    japaneseParticles.firstOrNull { segment.length > it.length && segment.endsWith(it) }
        ?.let { return end - it.length }

    for (particle in japaneseParticles) {
        val index = segment.lastIndexOf(particle)
        val boundary = index + particle.length
        // Require a lexical-looking span on both sides. Particle priority is
        // intentional: an unambiguous を must win over a later に that begins
        // a word such as にゅうりょく.
        if (index >= 2 && segment.length - boundary >= 2) {
            return start + boundary
        }
    }
    return start
}

private fun japaneseCharacterClass(codePoint: Int): JapaneseCharacterClass = when {
    codePoint in 0x3040..0x309F -> JapaneseCharacterClass.HIRAGANA
    codePoint in 0x30A0..0x30FF || codePoint in 0xFF66..0xFF9D ->
        JapaneseCharacterClass.KATAKANA
    codePoint in 0x3400..0x4DBF ||
        codePoint in 0x4E00..0x9FFF ||
        codePoint in 0xF900..0xFAFF -> JapaneseCharacterClass.HAN
    Character.isDigit(codePoint) -> JapaneseCharacterClass.DIGIT
    codePoint in 'A'.code..'Z'.code || codePoint in 'a'.code..'z'.code ->
        JapaneseCharacterClass.LATIN
    else -> JapaneseCharacterClass.OTHER
}

private fun containsWordCharacter(text: String, start: Int, end: Int): Boolean {
    var index = start
    while (index < end) {
        val codePoint = Character.codePointAt(text, index)
        if (Character.isLetterOrDigit(codePoint)) return true
        index += Character.charCount(codePoint)
    }
    return false
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
