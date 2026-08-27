package io.github.StupidGame.azookey_flutter.view

import android.content.Context
import android.graphics.Typeface
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.TextView

/**
 * A key face that keeps flick alternatives in their gesture directions.
 *
 * Gesture handling belongs to the IME service. This view only owns the visual
 * arrangement, so Custard actions and long-press state stay independent from
 * how their labels are presented.
 */
internal class DirectionalKeyView(
    context: Context,
    center: String,
    left: String?,
    up: String?,
    right: String?,
    down: String?,
    textColor: Int,
    centerTextSize: Float,
    directionTextSize: Float,
) : ViewGroup(context) {
    private enum class Position { CENTER, LEFT, UP, RIGHT, DOWN }

    private val cells = linkedMapOf<Position, TextView>()

    init {
        isClickable = true
        isFocusable = true
        contentDescription = listOfNotNull(
            center.takeIf(String::isNotEmpty),
            left?.takeIf(String::isNotEmpty)?.let { "左 $it" },
            up?.takeIf(String::isNotEmpty)?.let { "上 $it" },
            right?.takeIf(String::isNotEmpty)?.let { "右 $it" },
            down?.takeIf(String::isNotEmpty)?.let { "下 $it" },
        ).joinToString(", ")

        addCell(Position.CENTER, center, textColor, centerTextSize, maxLines = 2)
        addCell(Position.LEFT, left, textColor, directionTextSize)
        addCell(Position.UP, up, textColor, directionTextSize)
        addCell(Position.RIGHT, right, textColor, directionTextSize)
        addCell(Position.DOWN, down, textColor, directionTextSize)
    }

    private fun addCell(
        position: Position,
        value: String?,
        textColor: Int,
        size: Float,
        maxLines: Int = 1,
    ) {
        if (value.isNullOrEmpty()) return
        val cell = TextView(context).apply {
            text = value
            gravity = Gravity.CENTER
            includeFontPadding = false
            setTextColor(textColor)
            textSize = size
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
            isAllCaps = false
            this.maxLines = maxLines
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        cells[position] = cell
        addView(cell)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val height = MeasureSpec.getSize(heightMeasureSpec)
        setMeasuredDimension(
            resolveSize(width, widthMeasureSpec),
            resolveSize(height, heightMeasureSpec),
        )
        cells.forEach { (position, child) ->
            val widthFraction = when (position) {
                Position.CENTER -> 0.50f
                Position.UP, Position.DOWN -> 0.62f
                Position.LEFT, Position.RIGHT -> 0.35f
            }
            val heightFraction = when (position) {
                Position.CENTER -> 0.50f
                Position.UP, Position.DOWN -> 0.34f
                Position.LEFT, Position.RIGHT -> 0.46f
            }
            child.measure(
                MeasureSpec.makeMeasureSpec((width * widthFraction).toInt(), MeasureSpec.AT_MOST),
                MeasureSpec.makeMeasureSpec((height * heightFraction).toInt(), MeasureSpec.AT_MOST),
            )
        }
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val width = right - left
        val height = bottom - top
        cells.forEach { (position, child) ->
            val centerX = when (position) {
                Position.LEFT -> width * 0.17f
                Position.RIGHT -> width * 0.83f
                else -> width * 0.50f
            }
            val centerY = when (position) {
                Position.UP -> height * 0.17f
                Position.DOWN -> height * 0.83f
                else -> height * 0.50f
            }
            val childLeft = (centerX - child.measuredWidth / 2f).toInt()
            val childTop = (centerY - child.measuredHeight / 2f).toInt()
            child.layout(
                childLeft,
                childTop,
                childLeft + child.measuredWidth,
                childTop + child.measuredHeight,
            )
        }
    }
}
