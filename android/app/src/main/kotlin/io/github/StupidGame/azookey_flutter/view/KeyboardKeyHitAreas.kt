package io.github.StupidGame.azookey_flutter.view

import android.annotation.SuppressLint
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup

/** Fill the small visual gaps between keys without moving their painted bounds. */
@SuppressLint("ClickableViewAccessibility") // Events go to the original, accessible key.
internal fun ViewGroup.expandKeyboardKeyHitAreas(extra: Int) {
    val hitAreas = KeyboardKeyHitAreas(this, extra)
    setOnTouchListener(hitAreas)
    addOnAttachStateChangeListener(hitAreas)
}

private class KeyboardKeyHitAreas(
    private val host: ViewGroup,
    private val extra: Int,
) : View.OnTouchListener, View.OnAttachStateChangeListener {
    private var target: View? = null
    private var offsetX = 0f
    private var offsetY = 0f
    private var downTime = 0L

    override fun onTouch(view: View, event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN) {
            cancel()
            val x = event.x + host.scrollX
            val y = event.y + host.scrollY
            var nearest: View? = null
            var distance = Float.POSITIVE_INFINITY
            for (index in 0 until host.childCount) {
                val key = host.getChildAt(index)
                if (key.visibility != View.VISIBLE) continue
                // Do not borrow the actual area of spacers or disabled keys.
                if (x >= key.left && x < key.right && y >= key.top && y < key.bottom) return false
                if (!key.isEnabled || (!key.isClickable && !key.isLongClickable) || key.width <= 0 || key.height <= 0) continue
                if (x < key.left - extra || x >= key.right + extra ||
                    y < key.top - extra || y >= key.bottom + extra) continue
                val dx = x - x.coerceIn(key.left.toFloat(), key.right.toFloat())
                val dy = y - y.coerceIn(key.top.toFloat(), key.bottom.toFloat())
                val squared = dx * dx + dy * dy
                if (squared < distance) {
                    nearest = key
                    distance = squared
                }
            }
            val key = nearest ?: return false
            val localX = x - key.left
            val localY = y - key.top
            // Use one constant offset for the entire gesture. TouchDelegate's
            // centering on each event loses the movement needed by flick keys.
            offsetX = host.scrollX - key.left + localX.coerceIn(0f, (key.width - 1).toFloat()) - localX
            offsetY = host.scrollY - key.top + localY.coerceIn(0f, (key.height - 1).toFloat()) - localY
            downTime = event.downTime
            target = key
        }
        val key = target ?: return false
        if (key.parent !== host || !key.isEnabled || key.visibility != View.VISIBLE) {
            cancel()
            return true
        }
        val terminal = event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL
        if (terminal) target = null
        val forwarded = MotionEvent.obtain(event)
        val handled = try {
            forwarded.offsetLocation(offsetX, offsetY)
            key.dispatchTouchEvent(forwarded)
        } finally {
            forwarded.recycle()
        }
        if (!handled && event.actionMasked == MotionEvent.ACTION_DOWN) target = null
        return handled || event.actionMasked != MotionEvent.ACTION_DOWN
    }

    private fun cancel() {
        val key = target ?: return
        target = null
        val event = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), MotionEvent.ACTION_CANCEL, 0f, 0f, 0)
        try {
            key.dispatchTouchEvent(event)
        } finally {
            event.recycle()
        }
    }

    override fun onViewAttachedToWindow(view: View) = Unit
    override fun onViewDetachedFromWindow(view: View) = cancel()
}
