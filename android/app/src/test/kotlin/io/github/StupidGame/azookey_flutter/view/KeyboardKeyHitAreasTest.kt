package io.github.StupidGame.azookey_flutter.view

import android.app.Activity
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.ConscryptMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28, 36], manifest = Config.NONE)
@ConscryptMode(ConscryptMode.Mode.OFF)
class KeyboardKeyHitAreasTest {
    private lateinit var activity: Activity
    private lateinit var row: FrameLayout
    private lateinit var first: View
    private lateinit var second: View
    private val events = mutableListOf<Triple<Int, Float, Float>>()
    private var secondTouches = 0

    @Before fun setUp() {
        activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        row = FrameLayout(activity).apply { expandKeyboardKeyHitAreas(4) }
        first = View(activity).apply {
            isClickable = true
            setOnTouchListener { _, event ->
                events.add(Triple(event.actionMasked, event.x, event.y))
                true
            }
        }
        second = View(activity).apply {
            isClickable = true
            setOnTouchListener { _, _ -> secondTouches++; true }
        }
        row.addView(first, FrameLayout.LayoutParams(46, 46).apply { leftMargin = 2; topMargin = 2 })
        row.addView(second, FrameLayout.LayoutParams(46, 46).apply { leftMargin = 52; topMargin = 2 })
        activity.setContentView(row)
        layout()
    }

    @Test fun gapTouchGoesToTheNearestKeyAndPreservesFlickMovement() {
        assertTrue(touch(MotionEvent.ACTION_DOWN, 49f, 49f))
        touch(MotionEvent.ACTION_MOVE, 69f, 19f)
        touch(MotionEvent.ACTION_UP, 89f, 19f)
        assertEquals(listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE, MotionEvent.ACTION_UP), events.map { it.first })
        assertEquals(20f, events[1].second - events[0].second, 0.01f)
        assertEquals(-30f, events[1].third - events[0].third, 0.01f)
        assertEquals(40f, events[2].second - events[0].second, 0.01f)
        assertEquals(0, secondTouches)
    }

    @Test fun touchesInsideTheKeyKeepTheirOriginalCoordinates() {
        touch(MotionEvent.ACTION_DOWN, 12f, 22f)
        touch(MotionEvent.ACTION_UP, 12f, 22f)
        assertEquals(Triple(MotionEvent.ACTION_DOWN, 10f, 20f), events.first())
    }

    @Test fun cancellationDoesNotGenerateAnUpOrRetargetTheNextGesture() {
        touch(MotionEvent.ACTION_DOWN, 49f, 20f)
        touch(MotionEvent.ACTION_CANCEL, 49f, 20f)
        touch(MotionEvent.ACTION_DOWN, 51f, 20f)
        touch(MotionEvent.ACTION_UP, 51f, 20f)
        assertEquals(listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_CANCEL), events.map { it.first })
        assertEquals(2, secondTouches)
    }

    @Test fun detachingTheRowCancelsAHeldGapKey() {
        touch(MotionEvent.ACTION_DOWN, 49f, 20f)
        activity.setContentView(View(activity))
        assertEquals(MotionEvent.ACTION_CANCEL, events.last().first)
    }

    @Test fun removingAKeyCancelsInsteadOfContinuingOnItsNeighbor() {
        touch(MotionEvent.ACTION_DOWN, 49f, 20f)
        row.removeView(first)
        touch(MotionEvent.ACTION_UP, 60f, 20f)
        assertEquals(MotionEvent.ACTION_CANCEL, events.last().first)
        assertEquals(0, secondTouches)
    }

    @Test fun largeEmptyCellsAndDisabledKeysAreNotClaimed() {
        row.removeView(second)
        val spacer = View(activity)
        row.addView(spacer, FrameLayout.LayoutParams(46, 46).apply { leftMargin = 48; topMargin = 2 })
        layout()
        assertFalse(touch(MotionEvent.ACTION_DOWN, 49f, 20f))
        assertTrue(events.isEmpty())
        row.removeView(spacer)
        first.isEnabled = false
        assertFalse(touch(MotionEvent.ACTION_DOWN, 49f, 20f))
        assertFalse(touch(MotionEvent.ACTION_DOWN, 90f, 20f))
        assertTrue(events.isEmpty())
    }

    private fun layout() {
        row.measure(View.MeasureSpec.makeMeasureSpec(100, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(50, View.MeasureSpec.EXACTLY))
        row.layout(0, 0, 100, 50)
    }

    private fun touch(action: Int, x: Float, y: Float): Boolean {
        val now = SystemClock.uptimeMillis()
        val event = MotionEvent.obtain(now, now, action, x, y, 0)
        return try { row.dispatchTouchEvent(event) } finally { event.recycle() }
    }
}
