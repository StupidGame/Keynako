package io.github.StupidGame.azookey_flutter.input

internal data class KeyboardHeightMetrics(
    val rowHeight: Int,
    val minimumRowHeight: Int,
    val candidateBarHeight: Int,
    val candidatePanelHeight: Int,
    val maximumInputHeight: Int?,
) {
    fun maximumBodyHeight(bottomInset: Int, panelVisible: Boolean): Int? =
        maximumInputHeight?.let {
            (it - bottomInset - candidateBarHeight -
                if (panelVisible) candidatePanelHeight else 0).coerceAtLeast(1)
        }
}

/**
 * Use separate orientation metrics, as azooKey does in KeyboardViews/Design.swift:
 * https://github.com/azooKey/azooKey/blob/b50db4aec1069a8d2341f70415da3bdc61f1fce6/AzooKeyCore/Sources/KeyboardViews/Design.swift
 * Keep portrait sizes; reserve at least 45% of the landscape window for the editor.
 */
internal fun keyboardHeightMetrics(
    landscape: Boolean,
    availableHeight: Int,
    density: Float,
    heightScale: Double,
): KeyboardHeightMetrics {
    fun dp(value: Int) = (value * density).toInt().coerceAtLeast(1)
    val scale = heightScale.takeIf { it.isFinite() }?.coerceIn(0.7, 1.4) ?: 1.0
    val maximum = if (landscape) (availableHeight * 0.55).toInt().coerceAtLeast(1) else null
    return KeyboardHeightMetrics(
        rowHeight = (dp(if (landscape) 36 else 47) * scale).toInt().coerceAtLeast(1),
        minimumRowHeight = dp(if (landscape) 24 else 32),
        candidateBarHeight = dp(if (landscape) 32 else 43),
        candidatePanelHeight = if (maximum == null) dp(176) else minOf(dp(88), (maximum * 0.32).toInt()),
        maximumInputHeight = maximum,
    )
}

/** Fit ordinary layouts; keep very tall custom layouts readable inside a scroll viewport. */
internal fun keyboardBodyHeightScale(
    naturalHeight: Int,
    maximumHeight: Int?,
    rowHeight: Int,
    minimumRowHeight: Int,
): Double {
    if (maximumHeight == null || naturalHeight <= maximumHeight || naturalHeight <= 0) return 1.0
    val minimumScale = (minimumRowHeight.toDouble() / rowHeight.coerceAtLeast(1)).coerceAtMost(1.0)
    return (maximumHeight.toDouble() / naturalHeight).coerceIn(minimumScale, 1.0)
}
