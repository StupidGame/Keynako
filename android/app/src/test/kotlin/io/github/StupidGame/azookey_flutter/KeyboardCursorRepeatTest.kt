package io.github.StupidGame.azookey_flutter

import android.app.Activity
import android.content.Context
import android.os.Looper
import android.os.SystemClock
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputConnection
import android.widget.TextView
import java.lang.reflect.Proxy
import java.time.Duration
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.ConscryptMode
import org.robolectric.annotation.LooperMode
import org.robolectric.util.ReflectionHelpers
import org.robolectric.junit.rules.TimeoutRule

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28, 36], manifest = Config.NONE)
@ConscryptMode(ConscryptMode.Mode.OFF)
@LooperMode(LooperMode.Mode.PAUSED)
class KeyboardCursorRepeatTest {
    @get:Rule val timeout: TimeoutRule = TimeoutRule.seconds(20)

    private lateinit var service: AzooKeyInputMethodService
    private lateinit var activity: Activity
    private lateinit var frame: ViewGroup
    private val moves = mutableListOf<Int>()
    private val commits = mutableListOf<String>()
    private var document = "abcdefghijklmnopqrstuvwxyz".repeat(3)
    private var caret = 30
    private var previousWindowVisibilityProperty: String? = null

    @Before fun setUp() {
        // Legacy Robolectric graphics leave windows hidden unless requested.
        previousWindowVisibilityProperty = System.getProperty("robolectric.areWindowsMarkedVisible")
        System.setProperty("robolectric.areWindowsMarkedVisible", "true")
        service = Robolectric.buildService(AzooKeyInputMethodService::class.java).create().get()
        service.getSharedPreferences(MainActivity.PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit().clear().putString(MainActivity.STATE_KEY, JSONObject().put("settings", JSONObject()
                .put("enable_zenzai", false).put("long_press_duration_ms", 400)).toString()).commit()
        val connection = Proxy.newProxyInstance(InputConnection::class.java.classLoader,
            arrayOf(InputConnection::class.java)) { _, method, args ->
            when (method.name) {
                "getTextBeforeCursor" -> document.take(caret).takeLast(args[0] as Int)
                "getTextAfterCursor" -> document.drop(caret).take(args[0] as Int)
                "sendKeyEvent" -> {
                    val event = args[0] as KeyEvent
                    if (event.action == KeyEvent.ACTION_DOWN) {
                        val count = if (event.keyCode == KeyEvent.KEYCODE_DPAD_LEFT) -1 else 1
                        moves.add(count)
                        caret = (caret + count).coerceIn(0, document.length)
                    }
                    true
                }
                "commitText" -> { commits.add(args[0].toString()); true }
                else -> when (method.returnType) {
                    Boolean::class.javaPrimitiveType -> true
                    Int::class.javaPrimitiveType -> 0
                    else -> null
                }
            }
        } as InputConnection
        ReflectionHelpers.setField(service, "mStartedInputConnection", connection)
        frame = service.onCreateInputView() as ViewGroup
        activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        mount(frame)
    }

    @After fun tearDown() {
        if (::activity.isInitialized) activity.setContentView(View(activity))
        val previous = previousWindowVisibilityProperty
        if (previous == null) System.clearProperty("robolectric.areWindowsMarkedVisible")
        else System.setProperty("robolectric.areWindowsMarkedVisible", previous)
    }

    @Test fun customCursorKeysRepeatInBothDirectionsAndDoNotMoveAgainOnRelease() {
        for (count in listOf(-1, 1)) {
            val key = custom(JSONObject().put("tap", moveAction(count)))
            mount(key)
            assertHold(key, count)
        }
    }

    @Test fun custardCursorKeysRepeatWithoutChangingTheImportedDefinition() {
        for (count in listOf(-1, 1)) {
            val definition = JSONObject().put("press_actions", JSONArray().put(custardMove(count)))
            val key = custard(definition)
            mount(key)
            assertHold(key, count)
            assertFalse(definition.has("longpress_actions"))
        }
    }

    @Test fun aShortCursorTapMovesExactlyOnce() {
        for (key in listOf(custom(JSONObject().put("tap", moveAction(-1))),
            custard(JSONObject().put("press_actions", JSONArray().put(custardMove(1)))))) {
            mount(key)
            moves.clear()
            touch(key, MotionEvent.ACTION_DOWN)
            idle(100)
            touch(key, MotionEvent.ACTION_UP)
            idle(500)
            assertEquals(1, moves.size)
        }
    }

    @Test fun cancelAndDetachStopPendingAndActiveCursorRepeats() {
        for (factory in listOf<() -> View>(
            { custom(JSONObject().put("tap", moveAction(-1))) },
            { custard(JSONObject().put("press_actions", JSONArray().put(custardMove(1)))) },
        )) {
            var key = factory()
            mount(key)
            moves.clear()
            touch(key, MotionEvent.ACTION_DOWN)
            touch(key, MotionEvent.ACTION_CANCEL)
            idle(600)
            assertTrue(moves.isEmpty())
            touch(key, MotionEvent.ACTION_DOWN)
            idle(400)
            assertEquals(1, moves.size)
            activity.setContentView(View(activity))
            idle(500)
            assertEquals(1, moves.size)
            key = factory()
            mount(key)
            moves.clear()
            touch(key, MotionEvent.ACTION_DOWN)
            activity.setContentView(View(activity))
            idle(600)
            assertTrue(moves.isEmpty())
        }
    }

    @Test fun explicitCustomLongPressIsPreserved() {
        val key = custom(JSONObject().put("tap", moveAction(1)).put("longPress", moveAction(-2)))
        mount(key)
        touch(key, MotionEvent.ACTION_DOWN)
        idle(800)
        touch(key, MotionEvent.ACTION_UP)
        assertEquals(listOf(-1, -1), moves)
    }

    @Test fun hidingTheKeyboardStopsCursorRepeats() {
        val key = custom(JSONObject().put("tap", moveAction(1)))
        mount(key)
        touch(key, MotionEvent.ACTION_DOWN)
        idle(400)
        assertEquals(1, moves.size)
        key.rootView.visibility = View.GONE
        idle(500)
        assertEquals(1, moves.size)
        key.rootView.visibility = View.VISIBLE
        touch(key, MotionEvent.ACTION_CANCEL)
        touch(key, MotionEvent.ACTION_DOWN)
        idle(400)
        assertEquals(2, moves.size)
        touch(key, MotionEvent.ACTION_UP)
    }

    @Test fun explicitCustardLongPressAndRepeatArePreserved() {
        val key = custard(JSONObject().put("press_actions", JSONArray().put(custardMove(-1)))
            .put("longpress_actions", JSONObject().put("duration", "light")
                .put("start", JSONArray().put(custardMove(2)))
                .put("repeat", JSONArray().put(custardMove(3)))))
        mount(key)
        touch(key, MotionEvent.ACTION_DOWN)
        idle(125)
        assertEquals(2, moves.size)
        idle(70)
        assertEquals(5, moves.size)
        touch(key, MotionEvent.ACTION_UP)
        idle(500)
        assertEquals(List(5) { 1 }, moves)
    }

    @Test fun spaceFlicksRepeatLeftAndRightWithoutInsertingASpace() {
        val space = descendants(frame).filterIsInstance<TextView>().single { it.text.toString() == "空白" }
        for (count in listOf(-1, 1)) {
            moves.clear()
            val start = space.width / 2f
            val end = start + count * 30 * service.resources.displayMetrics.density
            touch(space, MotionEvent.ACTION_DOWN, start)
            touch(space, MotionEvent.ACTION_MOVE, end)
            idle(399)
            assertTrue(moves.isEmpty())
            idle(211)
            assertEquals(List(4) { count }, moves)
            touch(space, MotionEvent.ACTION_UP, end)
            idle(300)
            assertEquals(4, moves.size)
        }
        assertTrue(commits.isEmpty())
    }

    @Test fun customCursorFlicksAlsoRepeat() {
        val key = custom(JSONObject().put("label", "空白")
            .put("left", moveAction(-1)).put("right", moveAction(1)))
        mount(key)
        for (count in listOf(-1, 1)) {
            moves.clear()
            val start = key.width / 2f
            val end = start + count * 30 * service.resources.displayMetrics.density
            touch(key, MotionEvent.ACTION_DOWN, start)
            touch(key, MotionEvent.ACTION_MOVE, end)
            idle(610)
            assertEquals(List(4) { count }, moves)
            touch(key, MotionEvent.ACTION_UP, end)
            idle(500)
            assertEquals(4, moves.size)
        }
    }

    @Test fun shortSpaceFlickMovesOnceAndCancelStopsAHeldSpaceFlick() {
        val space = descendants(frame).filterIsInstance<TextView>().single { it.text.toString() == "空白" }
        val start = space.width / 2f
        val end = start - 30 * service.resources.displayMetrics.density
        touch(space, MotionEvent.ACTION_DOWN, start)
        touch(space, MotionEvent.ACTION_MOVE, end)
        idle(100)
        touch(space, MotionEvent.ACTION_UP, end)
        idle(500)
        assertEquals(listOf(-1), moves)
        touch(space, MotionEvent.ACTION_DOWN, start)
        touch(space, MotionEvent.ACTION_MOVE, end)
        idle(400)
        assertEquals(2, moves.size)
        touch(space, MotionEvent.ACTION_CANCEL, end)
        idle(500)
        assertEquals(2, moves.size)
        assertTrue(commits.isEmpty())
    }

    @Test fun cursorBarArrowsRepeatBothWaysWhenThereIsTextAfterTheCursor() {
        for (count in listOf(-1, 1)) {
            ReflectionHelpers.callInstanceMethod<Unit>(service, "renderCursorBar")
            mount(frame)
            shadowOf(Looper.getMainLooper()).idle()
            val bar = ReflectionHelpers.getField<View>(service, "cursorBarView")
            val x = if (count < 0) 1f else bar.width - 1f
            moves.clear()
            touch(bar, MotionEvent.ACTION_DOWN, x)
            idle(399)
            assertTrue(moves.isEmpty())
            idle(301)
            assertEquals(List(4) { count }, moves)
            touch(bar, MotionEvent.ACTION_UP, x)
            idle(500)
            assertEquals(4, moves.size)
        }
    }

    @Test fun heldCursorBarArrowsCrossLineBreaksInBothDirections() {
        document = "abc\ndef"
        for (count in listOf(-1, 1)) {
            caret = if (count < 0) 4 else 3
            ReflectionHelpers.callInstanceMethod<Unit>(service, "renderCursorBar")
            mount(frame)
            val bar = ReflectionHelpers.getField<View>(service, "cursorBarView")
            val x = if (count < 0) 1f else bar.width - 1f
            moves.clear()
            touch(bar, MotionEvent.ACTION_DOWN, x)
            idle(500)
            assertEquals(List(2) { count }, moves)
            assertEquals(if (count < 0) 2 else 5, caret)
            touch(bar, MotionEvent.ACTION_UP, x)
            idle(500)
            assertEquals(2, moves.size)
        }
    }

    private fun assertHold(key: View, count: Int) {
        moves.clear()
        touch(key, MotionEvent.ACTION_DOWN)
        idle(399)
        assertTrue(moves.isEmpty())
        idle(211)
        assertEquals(List(4) { count }, moves)
        touch(key, MotionEvent.ACTION_UP)
        idle(500)
        assertEquals(4, moves.size)
    }

    private fun moveAction(count: Int) = JSONObject().put("type", "moveCursor").put("value", count.toString())
    private fun custardMove(count: Int) = JSONObject().put("type", "move_cursor").put("count", count)
    private fun custom(key: JSONObject): View = ReflectionHelpers.callInstanceMethod(service, "createCustomKey",
        ReflectionHelpers.ClassParameter.from(JSONObject::class.java, key),
        ReflectionHelpers.ClassParameter.from(Double::class.javaPrimitiveType!!, 1.0))
    private fun custard(key: JSONObject): View = ReflectionHelpers.callInstanceMethod(service, "createCustardKey",
        ReflectionHelpers.ClassParameter.from(JSONObject::class.java, JSONObject().put("key", key)),
        ReflectionHelpers.ClassParameter.from(String::class.java, "tenkey_style"),
        ReflectionHelpers.ClassParameter.from(Double::class.javaPrimitiveType!!, 1.0),
        ReflectionHelpers.ClassParameter.from(Boolean::class.javaPrimitiveType!!, true))

    private fun mount(view: View) {
        if (view.parent == null) activity.setContentView(view)
        shadowOf(Looper.getMainLooper()).idle()
        view.measure(View.MeasureSpec.makeMeasureSpec(600, View.MeasureSpec.EXACTLY),
            if (view === frame) View.MeasureSpec.makeMeasureSpec(1000, View.MeasureSpec.AT_MOST)
            else View.MeasureSpec.makeMeasureSpec(50, View.MeasureSpec.EXACTLY))
        view.layout(0, 0, view.measuredWidth, view.measuredHeight)
        assertTrue("keyboard must be attached", view.isAttachedToWindow)
        assertTrue("keyboard must be shown", view.isShown)
        assertEquals("keyboard window must be visible", View.VISIBLE, view.windowVisibility)
    }

    private fun idle(ms: Long) = shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(ms))
    private fun descendants(group: ViewGroup): List<View> = (0 until group.childCount).flatMap {
        val child = group.getChildAt(it)
        listOf(child) + if (child is ViewGroup) descendants(child) else emptyList()
    }

    private fun touch(view: View, action: Int, x: Float = view.width / 2f) {
        val now = SystemClock.uptimeMillis()
        val event = MotionEvent.obtain(now, now, action, x, view.height / 2f, 0)
        try { assertTrue(view.dispatchTouchEvent(event)) } finally { event.recycle() }
    }
}
