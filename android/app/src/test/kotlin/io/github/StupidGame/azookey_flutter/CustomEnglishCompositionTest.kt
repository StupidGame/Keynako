package io.github.StupidGame.azookey_flutter

import android.content.Context
import android.view.inputmethod.InputConnection
import java.lang.reflect.Proxy
import org.json.JSONArray
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
import org.robolectric.util.ReflectionHelpers.ClassParameter

/** Exercises the real IME dispatcher and editor connection, including Custard action lists. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
// No network/crypto is exercised; keep the test runnable on Linux ARM64 as well.
@ConscryptMode(ConscryptMode.Mode.OFF)
class CustomEnglishCompositionTest {
    private lateinit var service: AzooKeyInputMethodService
    private val commits = mutableListOf<String>()
    private var markedText = ""

    @Before
    fun setUp() {
        service = Robolectric.buildService(AzooKeyInputMethodService::class.java).create().get()
        // Names deliberately do not identify Shift or Caps Lock: semantics come from metadata.
        val state = JSONObject().put("settings", JSONObject()
            .put("enable_zenzai", false)
            .put("memory_learining_styple_setting", 2))
            .put("custards", JSONArray()
                .put(custard("letters-one", "en_US"))
                .put(custard("letters-two", "en_US"))
                .put(custard("letters-three", "en_US"))
                .put(custard("kana", "ja_JP"))
                .put(custard("romaji", "ja_JP", "roman2kana"))
                .put(custard("literal", "none")))
            .put("customTabs", JSONArray().put(JSONObject()
                .put("id", "my-letters")
                .put("language", "en_US")
                .put("inputStyle", "direct")
                .put("keys", JSONArray())))
        service.getSharedPreferences(MainActivity.PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit().putString(MainActivity.STATE_KEY, state.toString()).commit()
        service.onCreateInputView()
        val connection = Proxy.newProxyInstance(
            InputConnection::class.java.classLoader,
            arrayOf(InputConnection::class.java),
        ) { _, method, arguments ->
            when (method.name) {
                "setComposingText" -> {
                    markedText = arguments[0].toString()
                    true
                }
                "commitText" -> {
                    commits += arguments[0].toString()
                    markedText = ""
                    true
                }
                else -> when (method.returnType) {
                    Boolean::class.javaPrimitiveType -> false
                    Int::class.javaPrimitiveType -> 0
                    else -> null
                }
            }
        } as InputConnection
        ReflectionHelpers.setField(service, "mStartedInputConnection", connection)
        selectTab("custom:letters-one")
    }

    @Test
    fun shiftTabAndAutomaticReturnKeepTheWholeWordUncommitted() {
        input("h")
        moveTab("letters-two")
        assertComposing("h")

        // A shifted Custard key inputs an uppercase letter and returns in the same action list.
        dispatchActions(JSONArray()
            .put(JSONObject().put("type", "input").put("text", "A"))
            .put(tabAction("letters-one")))
        assertComposing("hA")
        input("n")
        assertComposing("hAn")
        assertEquals("letters-one", ReflectionHelpers.getField<String>(service, "activeCustomTab"))
    }

    @Test
    fun uppercaseFirstLetterAndAutomaticReturnStayUncommitted() {
        moveTab("letters-two")
        dispatchActions(JSONArray()
            .put(JSONObject().put("type", "input").put("text", "A"))
            .put(tabAction("letters-one")))
        assertComposing("A")
        input("b")
        assertComposing("Ab")
    }

    @Test
    fun capsLockTabAndReturnKeepExistingAndSubsequentLetters() {
        input("a")
        moveTab("letters-three")
        input("B")
        input("C")
        assertComposing("aBC")
        moveTab("letters-one")
        input("d")
        assertComposing("aBCd")
    }

    @Test
    fun tabBarAndSystemEnglishLayoutKeepTheSameComposition() {
        input("a")
        selectTab("custom:my-letters")
        dispatch(JSONObject().put("type", "input").put("value", "B"))
        assertComposing("aB")
        dispatch(tabAction("qwerty_english", "system"))
        dispatch(JSONObject().put("type", "input").put("value", "c"))
        assertComposing("aBc")
        dispatch(tabAction("user_english", "system"))
        assertComposing("aBc")
        selectTab("english")
        assertComposing("aBc")
    }

    @Test
    fun builtInShiftKeepsTheWordAndResetsAfterOneLetter() {
        dispatch(tabAction("qwerty_english", "system"))
        dispatch(JSONObject().put("type", "input").put("value", "h"))
        ReflectionHelpers.callInstanceMethod<Unit>(
            service, "dispatchNamedAction", ClassParameter.from(String::class.java, "shiftEnglish"),
        )
        assertComposing("h")
        dispatch(JSONObject().put("type", "input").put("value", "a"))
        dispatch(JSONObject().put("type", "input").put("value", "n"))
        assertComposing("hAn")
    }

    @Test
    fun languageChangeStillCommitsThePreviousComposition() {
        input("a")
        moveTab("kana")
        assertEquals(1, commits.size)
        assertEquals("", ReflectionHelpers.getField<String>(service, "composing"))
        assertEquals("japanese", ReflectionHelpers.getField<String>(service, "mode"))
    }

    @Test
    fun japaneseDirectCustardCommitsAsciiSyntaxVerbatim() {
        moveTab("kana")
        input("$[x2 ]")

        assertEquals(listOf("$[x2 ]"), commits)
        assertEquals("", ReflectionHelpers.getField<String>(service, "composing"))
        assertEquals("", ReflectionHelpers.getField<String>(service, "rawRoman"))
        assertEquals("", markedText)
    }

    @Test
    fun japaneseRoman2KanaCustardStillConvertsAscii() {
        moveTab("romaji")
        input("ka")

        assertEquals("ka", ReflectionHelpers.getField<String>(service, "rawRoman"))
        assertEquals("か", ReflectionHelpers.getField<String>(service, "composing"))
        assertTrue("Unexpected editor commits: $commits", commits.isEmpty())
    }

    @Test
    fun directInputTabStillCommitsAndMissingTabDoesNothing() {
        input("a")
        moveTab("missing-layout")
        assertComposing("a")
        assertEquals("letters-one", ReflectionHelpers.getField<String>(service, "activeCustomTab"))
        moveTab("literal")
        assertEquals(1, commits.size)
        input("B")
        assertEquals("B", commits.last())
        assertEquals("", ReflectionHelpers.getField<String>(service, "composing"))
    }

    private fun assertComposing(expected: String) {
        assertEquals(expected, ReflectionHelpers.getField<String>(service, "composing"))
        assertEquals(expected, markedText)
        assertTrue("Unexpected editor commits: $commits", commits.isEmpty())
        val candidates = ReflectionHelpers.getField<List<String>>(service, "candidates")
        assertTrue("Missing whole-word candidate: $candidates", expected in candidates)
    }

    private fun input(text: String) = dispatch(JSONObject().put("type", "input").put("text", text))

    private fun moveTab(id: String) = dispatch(tabAction(id))

    private fun tabAction(id: String, type: String = "custom") = JSONObject()
        .put("type", "move_tab").put("tab_type", type).put("identifier", id)

    private fun selectTab(value: String) = ReflectionHelpers.callInstanceMethod<Unit>(
        service, "selectTab", ClassParameter.from(String::class.java, value),
    )

    private fun dispatch(action: JSONObject) = ReflectionHelpers.callInstanceMethod<Unit>(
        service, "dispatchAction",
        ClassParameter.from(JSONObject::class.java, action),
        ClassParameter.from(Boolean::class.javaPrimitiveType, false),
    )

    private fun dispatchActions(actions: JSONArray) = ReflectionHelpers.callInstanceMethod<Unit>(
        service, "dispatchActions",
        ClassParameter.from(JSONArray::class.java, actions),
        ClassParameter.from(Int::class.javaPrimitiveType, 0),
        ClassParameter.from(Boolean::class.javaPrimitiveType, false),
    )

    private fun custard(
        id: String,
        language: String,
        inputStyle: String = "direct",
    ) = JSONObject()
        .put("identifier", id).put("language", language).put("input_style", inputStyle)
        .put("interface", JSONObject().put("key_style", "pc_style")
            .put("key_layout", JSONObject().put("type", "grid_fit")
                .put("row_count", 1).put("column_count", 1))
            .put("keys", JSONArray()))
}
