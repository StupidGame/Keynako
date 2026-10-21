package io.github.StupidGame.azookey_flutter

import android.content.Context
import android.text.InputType
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import java.lang.reflect.Proxy
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
@ConscryptMode(ConscryptMode.Mode.OFF)
class InputPrivacyTest {
    private lateinit var service: AzooKeyInputMethodService
    private val commits = mutableListOf<String>()
    private val compositions = mutableListOf<String>()

    @Before fun setUp() {
        service = Robolectric.buildService(AzooKeyInputMethodService::class.java).create().get()
        val state = JSONObject().put("settings", JSONObject()
            .put("enable_zenzai", false).put("live_conversion", false)
            .put("enable_wrong_conversion_report", true).put("wrong_conversion_report_frequency", 1))
            .put("learning", JSONObject().put("en:private\tPrivateWord", 7))
            .put("userDictionary", JSONArray())
        service.getSharedPreferences(MainActivity.PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit().putString(MainActivity.STATE_KEY, state.toString()).commit()
        service.onCreateInputView()
        val connection = Proxy.newProxyInstance(InputConnection::class.java.classLoader,
            arrayOf(InputConnection::class.java)) { _, method, arguments ->
            when (method.name) {
                "commitText" -> commits.add(arguments[0].toString())
                "setComposingText" -> compositions.add(arguments[0].toString())
            }
            when (method.returnType) {
                Boolean::class.javaPrimitiveType -> true
                Int::class.javaPrimitiveType -> 0
                else -> null
            }
        } as InputConnection
        ReflectionHelpers.setField(service, "mStartedInputConnection", connection)
    }

    @Test fun passwordContentsStayOutOfCompositionAfterChangingKeyboardLanguage() {
        for (inputType in listOf(
            InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD,
            InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD,
            InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
            InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
        )) {
            startInput(inputType)
            invoke("selectTab", "japanese")
            for (method in listOf("inputText", "customInput", "custardInput")) {
                invoke(method, "あ?([123")
                assertEquals("あ?([123", commits.last())
            }
            assertTrue(compositions.isEmpty())
            assertTrue(ReflectionHelpers.getField<List<String>>(service, "candidates").isEmpty())
        }
        assertEquals(1, storedLearning().length())
    }

    @Test fun privateEditorStillComposesButDoesNotReadOrWritePersonalizedHistory() {
        startInput(InputType.TYPE_CLASS_TEXT, EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING)
        invoke("selectTab", "english")
        invoke("inputText", "private")
        assertTrue(compositions.isNotEmpty())
        assertTrue(ReflectionHelpers.callInstanceMethod<Map<String, Int>>(service, "learningScores").isEmpty())
        ReflectionHelpers.callInstanceMethod<Unit>(service, "commitComposition",
            ClassParameter.from(Boolean::class.javaPrimitiveType, true))
        assertTrue(commits.isNotEmpty())
        assertEquals(1, storedLearning().length())

        // A later ordinary editor must resume normal learning.
        startInput(InputType.TYPE_CLASS_TEXT)
        invoke("selectTab", "english")
        invoke("inputText", "ordinary")
        ReflectionHelpers.callInstanceMethod<Unit>(service, "commitComposition",
            ClassParameter.from(Boolean::class.javaPrimitiveType, true))
        assertTrue(storedLearning().length() > 1)
    }

    @Test fun editorChangesClearPendingReportsBeforeTheInputViewStarts() {
        val report = WrongConversionReport("元", "秘密", 1, "ひみつ", "himitsu", "roman2kana",
            "", "", "qwerty", "1", "default")
        ReflectionHelpers.setField(service, "pendingReport", report)
        service.onStartInput(EditorInfo().apply {
            inputType = InputType.TYPE_CLASS_TEXT
            imeOptions = EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
        }, false)
        assertNull(ReflectionHelpers.getField<WrongConversionReport?>(service, "pendingReport"))
        ReflectionHelpers.callInstanceMethod<Unit>(service, "maybeOfferReport",
            ClassParameter.from(WrongConversionReport::class.java, report))
        assertNull(ReflectionHelpers.getField<WrongConversionReport?>(service, "pendingReport"))
    }

    private fun startInput(type: Int, options: Int = 0) {
        val info = EditorInfo().apply { inputType = type; imeOptions = options }
        service.onStartInput(info, false)
        service.onStartInputView(info, false)
    }

    private fun storedLearning(): JSONObject = JSONObject(service.getSharedPreferences(
        MainActivity.PREFERENCES_NAME, Context.MODE_PRIVATE,
    ).getString(MainActivity.STATE_KEY, null)!!).getJSONObject("learning")

    private fun invoke(method: String, value: String) = ReflectionHelpers.callInstanceMethod<Unit>(
        service, method, ClassParameter.from(String::class.java, value),
    )
}
