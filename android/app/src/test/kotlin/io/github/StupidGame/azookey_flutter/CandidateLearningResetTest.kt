package io.github.StupidGame.azookey_flutter

import android.content.Context
import io.github.StupidGame.azookey_flutter.conversion.predictionResetKey
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
                .put("かめんらいだー\t学習リセット確認用の単語", 32)
                .put("context:4eca\tかめんらいだー\t学習リセット確認用の単語", 16)
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

    @Test fun resettingADictionaryWordKeepsItsOrdinaryCandidate() {
        val state = ReflectionHelpers.getField<JSONObject>(service, "state")
        state.put("learning", JSONObject().put("にほんご\t日本語", 32).put("ねこ\t猫", 8))
        ReflectionHelpers.setField(service, "composing", "にほんご")
        renderCandidates()
        val row = ReflectionHelpers.getField<ViewGroup>(service, "candidateRow")
        assertTrue(labels(row).first { it.text == "日本語" }.performLongClick())
        labels(keyboard).first { it.text == "この単語の学習をリセット" }.performClick()
        assertFalse(state.getJSONObject("learning").has("にほんご\t日本語"))
        assertEquals(8, state.getJSONObject("learning").getInt("ねこ\t猫"))
        val candidates = ReflectionHelpers.getField<List<String>>(service, "candidates")
        assertTrue("日本語" in candidates)
        assertEquals("にほんご", ReflectionHelpers.getField<String>(service, "composing"))
    }

    @Test fun kintetsuPhraseDoesNotReturnFromAnotherReadingOrDictionaryPrediction() {
        val word = "近鉄四日市駅から"
        val ruby = "きんてつよっかいちえきから"
        val state = ReflectionHelpers.getField<JSONObject>(service, "state")
        state.put("learning", JSONObject().put("$ruby\t$word", 32)
            .put("きんてつ\t$word", 8).put("context:4eca\tきんてつよっかいち\t$word", 16)
            .put("ねこ\t猫", 8))
        state.put("userDictionary", org.json.JSONArray().put(JSONObject()
            .put("id", 1).put("ruby", ruby).put("word", word).put("importance", 3)))
        ReflectionHelpers.setField(service, "composing", "きんてつ")
        renderCandidates()
        val row = ReflectionHelpers.getField<ViewGroup>(service, "candidateRow")
        assertTrue(labels(row).first { it.text == word }.performLongClick())
        labels(keyboard).first { it.text == "この単語の学習をリセット" }.performClick()
        val learning = state.getJSONObject("learning")
        assertEquals(2, learning.length())
        assertTrue(learning.has(predictionResetKey(word)))
        assertEquals(word, state.getJSONArray("userDictionary").getJSONObject(0).getString("word"))
        repeat(2) {
            renderCandidates()
            assertFalse(word in ReflectionHelpers.getField<List<String>>(service, "candidates"))
        }
        service.onDestroy()
        service = Robolectric.buildService(AzooKeyInputMethodService::class.java).create().get()
        keyboard = service.onCreateInputView()
        ReflectionHelpers.setField(service, "rawRoman", "")
        ReflectionHelpers.setField(service, "composing", "きんてつ")
        renderCandidates()
        assertFalse(word in ReflectionHelpers.getField<List<String>>(service, "candidates"))
        ReflectionHelpers.setField(service, "composing", ruby)
        renderCandidates()
        assertTrue(word in ReflectionHelpers.getField<List<String>>(service, "candidates"))
    }

    @Test fun returningFromTheMenuKeepsLearningAndComposition() {
        val row = ReflectionHelpers.getField<ViewGroup>(service, "candidateRow")
        assertTrue(labels(row).first { it.text == "学習リセット確認用の単語" }.performLongClick())
        assertTrue(labels(keyboard).any { it.text == "この単語の学習をリセット" })
        labels(keyboard).first { it.text == "戻る" }.performClick()
        val state = ReflectionHelpers.getField<JSONObject>(service, "state")
        assertEquals(32, state.getJSONObject("learning").getInt("かめんらいだー\t学習リセット確認用の単語"))
        assertEquals("かめ", ReflectionHelpers.getField<String>(service, "composing"))
    }

    private fun resetFrom(field: String) {
        val container = ReflectionHelpers.getField<ViewGroup>(service, field)
        assertTrue(labels(container).first { it.text == "学習リセット確認用の単語" }.performLongClick())
        labels(keyboard).first { it.text == "この単語の学習をリセット" }.performClick()
        val saved = service.getSharedPreferences(MainActivity.PREFERENCES_NAME, Context.MODE_PRIVATE)
            .getString(MainActivity.STATE_KEY, "{}")!!
        val learning = JSONObject(saved).getJSONObject("learning")
        assertEquals(2, learning.length())
        assertEquals(1, learning.getInt(predictionResetKey("学習リセット確認用の単語")))
        assertEquals(8, learning.getInt("ねこ\t猫"))
        assertEquals("かめ", ReflectionHelpers.getField<String>(service, "composing"))
        val candidates = ReflectionHelpers.getField<List<String>>(service, "candidates")
        assertFalse("学習リセット確認用の単語" in candidates)
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
