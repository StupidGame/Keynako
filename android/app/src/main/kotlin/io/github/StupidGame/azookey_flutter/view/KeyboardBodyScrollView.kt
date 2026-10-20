package io.github.StupidGame.azookey_flutter.view

import android.content.Context
import android.view.MotionEvent
import android.view.View
import android.widget.ScrollView

/** A bounded fallback for custom layouts that cannot fit without making keys too small. */
internal class KeyboardBodyScrollView(context: Context) : ScrollView(context) {
    var maximumHeight: Int? = null
        set(value) {
            if (field == value) return
            field = value
            requestLayout()
        }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val maximum = maximumHeight
        if (maximum == null) {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec)
            return
        }
        val available = if (View.MeasureSpec.getMode(heightMeasureSpec) == View.MeasureSpec.UNSPECIFIED) {
            maximum
        } else {
            minOf(maximum, View.MeasureSpec.getSize(heightMeasureSpec))
        }
        super.onMeasure(widthMeasureSpec, View.MeasureSpec.makeMeasureSpec(available, View.MeasureSpec.AT_MOST))
    }

    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        // A non-scrolling wrapper must never steal vertical flicks from keys.
        if (!canScrollVertically(-1) && !canScrollVertically(1)) return false
        return super.onInterceptTouchEvent(event)
    }
}
