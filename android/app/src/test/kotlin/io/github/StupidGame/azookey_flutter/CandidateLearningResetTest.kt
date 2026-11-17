package io.github.StupidGame.azookey_flutter

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import org.json.JSONObject
import org.junit.After
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
import org.robolectric.util.ReflectionHelpers
import org.robolectric.util.ReflectionHelpers.ClassParameter

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
@ConscryptMode(ConscryptMode.Mode.OFF)
class CandidateLearningResetTest {
    private lateinit var service: AzooKeyInputMethodService
    private lateinit var keyboard: View

    @Before fun setUp() {
        service = Robolectric.buildService(AzooKeyInputMethodService::class.java).create().get()
        val state = JSONObject()
            .put("settings", JSONObject().put("enable_zenzai", false).put("live_conversion", false))
            .put("learning", JSONObject()
                .put("かめんらいだー\t仮面ライダー", 32)
                .put("context:4eca\tかめんらいだー\t仮面ライダー", 16)
                .put("ねこ\t猫", 8))
        service.getSharedPreferences(MainActivity.PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit().clear().putString(MainActivity.STATE_KEY, state.toString()).commit()
        keyboard = service.onCreateInputView()
        ReflectionHelpers.setField(service, "composing", "かめ")
        ReflectionHelpers.setField(service, "rawRoman", "")
        renderCandidates()
    }

    @After fun tearDown() { service.onDestroy() }

    @Test fun resetsPredictionFromTheCandidateBarAndPersistsIt() {
        resetFrom("candidateRow")
    }

    @Test fun resetsPredictionFromTheExpandedCandidateGrid() {
        ReflectionHelpers.setField(service, "candidateExpanded", true)
        renderCandidates()
        resetFrom("candidatePanelContent")
    }

    @Test fun returningFromTheMenuKeepsLearningAndComposition() {
        val row = ReflectionHelpers.getField<ViewGroup>(service, "candidateRow")
        assertTrue(labels(row).first { it.text == "仮面ライダー" }.performLongClick())
        assertTrue(labels(keyboard).any { it.text == "この単語の学習をリセット" })
        labels(keyboard).first { it.text == "戻る" }.performClick()
        val state = ReflectionHelpers.getField<JSONObject>(service, "state")
        assertEquals(32, state.getJSONObject("learning").getInt("かめんらいだー\t仮面ライダー"))
        assertEquals("かめ", ReflectionHelpers.getField<String>(service, "composing"))
    }

    private fun resetFrom(field: String) {
        val container = ReflectionHelpers.getField<ViewGroup>(service, field)
        assertTrue(labels(container).first { it.text == "仮面ライダー" }.performLongClick())
        labels(keyboard).first { it.text == "この単語の学習をリセット" }.performClick()
        val saved = service.getSharedPreferences(MainActivity.PREFERENCES_NAME, Context.MODE_PRIVATE)
            .getString(MainActivity.STATE_KEY, "{}")!!
        val learning = JSONObject(saved).getJSONObject("learning")
        assertEquals(1, learning.length())
        assertEquals(8, learning.getInt("ねこ\t猫"))
        assertEquals("かめ", ReflectionHelpers.getField<String>(service, "composing"))
        val candidates = ReflectionHelpers.getField<List<String>>(service, "candidates")
        assertFalse("仮面ライダー" in candidates)
    }

    private fun renderCandidates() {
        ReflectionHelpers.callInstanceMethod<Unit>(service, "renderCandidates",
            ClassParameter.from(Boolean::class.javaPrimitiveType, false))
    }

    private fun labels(view: View): List<TextView> = when (view) {
        is TextView -> listOf(view)
        is ViewGroup -> (0 until view.childCount).flatMap { labels(view.getChildAt(it)) }
        else -> emptyList()
    }
}
