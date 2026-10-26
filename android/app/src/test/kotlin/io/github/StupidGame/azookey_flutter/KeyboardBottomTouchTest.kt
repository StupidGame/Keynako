package io.github.StupidGame.azookey_flutter

import android.app.Activity
import android.content.Context
import android.graphics.Insets
import android.os.Build
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.inputmethod.InputConnection
import android.widget.FrameLayout
import android.widget.TextView
import io.github.StupidGame.azookey_flutter.view.CustardGridLayout
import java.lang.reflect.Proxy
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.ConscryptMode
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29, 36], manifest = Config.NONE)
@ConscryptMode(ConscryptMode.Mode.OFF)
class KeyboardBottomTouchTest {
    private lateinit var service: AzooKeyInputMethodService
    private lateinit var frame: ViewGroup

    @Before fun setUp() {
        service = Robolectric.buildService(AzooKeyInputMethodService::class.java).create().get()
        service.getSharedPreferences(MainActivity.PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit().clear().putString(MainActivity.STATE_KEY, JSONObject().put("settings", JSONObject()
                .put("enable_zenzai", false).put("live_conversion", false)).toString()).commit()
        frame = service.onCreateInputView() as ViewGroup
        Robolectric.buildActivity(Activity::class.java).setup().get().setContentView(frame)
        layout()
    }

    @Test fun gestureInsetsMoveBottomKeysUpWithoutChangingPortraitKeyHeights() {
        val key = descendants(frame).filterIsInstance<TextView>().first { it.text.toString() == "わ" }
        val height = key.height
        frame.dispatchApplyWindowInsets(gestureInsets(bottom = 32))
        layout()
        val bottom = bottomInFrame(key)
        assertEquals(32, frame.paddingBottom)
        assertEquals(frame.height - 32 - dp(2), bottom)
        assertEquals(height, key.height)
        frame.dispatchApplyWindowInsets(gestureInsets(bottom = 32))
        layout()
        assertEquals(bottom, bottomInFrame(key))
        frame.dispatchApplyWindowInsets(gestureInsets(bottom = 0))
        layout()
        assertEquals(0, frame.paddingBottom)
    }

    @Test fun bottomFlickKeyAcceptsItsGapAndKeepsTheFlickDirection() {
        frame.dispatchApplyWindowInsets(gestureInsets(bottom = 32))
        layout()
        val grid = descendants(frame).filterIsInstance<CustardGridLayout>().single()
        val key = descendants(grid).filterIsInstance<TextView>().first { it.text.toString() == "わ" }
        val x = (key.left + key.right) / 2f
        val y = key.bottom + 1f
        touch(grid, MotionEvent.ACTION_DOWN, x, y)
        touch(grid, MotionEvent.ACTION_UP, x, y)
        assertEquals("わ", ReflectionHelpers.getField<String>(service, "composing"))
        ReflectionHelpers.setField(service, "composing", "")
        touch(grid, MotionEvent.ACTION_DOWN, x, y)
        touch(grid, MotionEvent.ACTION_MOVE, x, y - dp(30))
        touch(grid, MotionEvent.ACTION_UP, x, y - dp(30))
        assertEquals("ん", ReflectionHelpers.getField<String>(service, "composing"))
    }

    @Test fun qwertySpaceCanBeTappedAtTheBottomEdgeOfItsRow() {
        val commits = mutableListOf<String>()
        val connection = Proxy.newProxyInstance(InputConnection::class.java.classLoader,
            arrayOf(InputConnection::class.java)) { _, method, args ->
            if (method.name == "commitText") commits.add(args[0].toString())
            when (method.returnType) {
                Boolean::class.javaPrimitiveType -> true
                Int::class.javaPrimitiveType -> 0
                else -> null
            }
        } as InputConnection
        ReflectionHelpers.setField(service, "mStartedInputConnection", connection)
        ReflectionHelpers.setField(service, "mode", "english")
        ReflectionHelpers.setField(service, "layout", "qwerty")
        ReflectionHelpers.callInstanceMethod<Unit>(service, "renderKeyboard")
        layout()
        val space = descendants(frame).filterIsInstance<TextView>().single { it.text.toString() == "space" }
        val row = space.parent as ViewGroup
        val x = (space.left + space.right) / 2f
        val y = row.height - 1f
        assertTrue(y >= space.bottom)
        touch(row, MotionEvent.ACTION_DOWN, x, y)
        touch(row, MotionEvent.ACTION_UP, x, y)
        assertEquals(listOf(" "), commits)
    }

    @Test fun oneHandedWidthAndPositionUseTheSpaceInsideSideInsets() {
        ReflectionHelpers.setField(service, "oneHandedMode", "right")
        ReflectionHelpers.setField(service, "oneHandedWidth", 0.78f)
        frame.dispatchApplyWindowInsets(gestureInsets(bottom = 20, left = 30, right = 12))
        layout()
        val surface = ReflectionHelpers.getField<FrameLayout>(service, "keyboardSurface")
        assertEquals(((600 - 30 - 12) * 0.78f).toInt(), surface.width)
        assertEquals(600 - 12, surface.right)
    }

    @Suppress("DEPRECATION")
    private fun gestureInsets(bottom: Int, left: Int = 0, right: Int = 0): WindowInsets = WindowInsets.Builder().apply {
        if (Build.VERSION.SDK_INT >= 30) {
            setInsets(WindowInsets.Type.navigationBars(), Insets.of(left, 0, right, 0))
            setInsets(WindowInsets.Type.systemGestures(), Insets.of(24, 0, 24, bottom))
            setInsets(WindowInsets.Type.mandatorySystemGestures(), Insets.of(0, 0, 0, bottom))
        } else {
            setSystemWindowInsets(Insets.of(left, 0, right, 0))
            setSystemGestureInsets(Insets.of(24, 0, 24, bottom))
            setMandatorySystemGestureInsets(Insets.of(0, 0, 0, bottom))
        }
    }.build()

    private fun layout() {
        frame.measure(View.MeasureSpec.makeMeasureSpec(600, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(1000, View.MeasureSpec.AT_MOST))
        frame.layout(0, 0, frame.measuredWidth, frame.measuredHeight)
    }

    private fun bottomInFrame(key: View): Int {
        var bottom = key.height
        var view = key
        while (view !== frame) {
            bottom += view.top
            view = view.parent as View
        }
        return bottom
    }

    private fun descendants(group: ViewGroup): List<View> = (0 until group.childCount).flatMap {
        val child = group.getChildAt(it)
        listOf(child) + if (child is ViewGroup) descendants(child) else emptyList()
    }

    private fun dp(value: Int) = (value * service.resources.displayMetrics.density).toInt()

    private fun touch(view: View, action: Int, x: Float, y: Float) {
        val now = SystemClock.uptimeMillis()
        val event = MotionEvent.obtain(now, now, action, x, y, 0)
        try { assertTrue(view.dispatchTouchEvent(event)) } finally { event.recycle() }
    }
}
