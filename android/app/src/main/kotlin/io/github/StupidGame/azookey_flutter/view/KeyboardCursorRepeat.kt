package io.github.StupidGame.azookey_flutter.view

import android.os.Handler
import android.os.Looper
import android.view.View

/** Repeats a selected cursor flick while preserving a single step for short flicks. */
internal class KeyboardCursorRepeat(
    private val view: View,
    private val delayMillis: () -> Long,
    private val move: (Int) -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var offset = 0
    var didRepeat = false
        private set
    private val repeat = object : Runnable {
        override fun run() {
            if (offset == 0 || !view.isShown || view.windowVisibility != View.VISIBLE) {
                stop()
                return
            }
            didRepeat = true
            move(offset)
            if (offset != 0) handler.postDelayed(this, 70)
        }
    }

    init {
        view.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) = Unit
            override fun onViewDetachedFromWindow(view: View) = stop()
        })
    }

    fun reset() {
        stop()
        didRepeat = false
    }

    fun select(count: Int) {
        if (offset == count) return
        stop()
        offset = count
        if (offset != 0) handler.postDelayed(repeat, delayMillis())
    }

    fun stop() {
        handler.removeCallbacks(repeat)
        offset = 0
    }
}
