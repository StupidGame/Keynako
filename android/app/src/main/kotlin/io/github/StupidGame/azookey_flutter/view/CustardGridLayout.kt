package io.github.StupidGame.azookey_flutter.view

import android.content.Context
import android.view.View
import android.view.ViewGroup

/** Positions custom-layout keys on fractional rows and columns. */
internal class CustardGridLayout(
    context: Context,
    private val columns: Int,
    private val rows: Int,
) : ViewGroup(context) {
    private data class Position(
        val x: Double,
        val y: Double,
        val width: Double,
        val height: Double,
    )

    private val positions = linkedMapOf<View, Position>()
    private val gap = (2 * resources.displayMetrics.density).toInt()

    fun addPositionedView(
        view: View,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
    ) {
        positions[view] = Position(x, y, width, height)
        addView(view, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val measuredWidth = MeasureSpec.getSize(widthMeasureSpec)
        val measuredHeight = MeasureSpec.getSize(heightMeasureSpec)
        setMeasuredDimension(measuredWidth, measuredHeight)
        for ((view, position) in positions) {
            val childWidth = ((position.width / columns) * measuredWidth).toInt() - gap * 2
            val childHeight = ((position.height / rows) * measuredHeight).toInt() - gap * 2
            view.measure(
                MeasureSpec.makeMeasureSpec(childWidth.coerceAtLeast(1), MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(childHeight.coerceAtLeast(1), MeasureSpec.EXACTLY),
            )
        }
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val availableWidth = right - left
        val availableHeight = bottom - top
        for ((view, position) in positions) {
            val childLeft = ((position.x / columns) * availableWidth).toInt() + gap
            val childTop = ((position.y / rows) * availableHeight).toInt() + gap
            view.layout(childLeft, childTop, childLeft + view.measuredWidth, childTop + view.measuredHeight)
        }
    }
}
