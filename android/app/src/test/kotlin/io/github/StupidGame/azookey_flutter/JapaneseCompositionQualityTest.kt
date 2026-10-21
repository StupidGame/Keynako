package io.github.StupidGame.azookey_flutter

import android.content.Context
import android.view.inputmethod.InputConnection
import android.widget.LinearLayout
import android.widget.TextView
import io.github.StupidGame.azookey_flutter.conversion.DictionaryCandidates
import java.lang.reflect.Proxy
import org.json.JSONArray
import org.json.JSONObject
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

/** Checks the service path that was bypassing the existing spelling preference. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
@ConscryptMode(ConscryptMode.Mode.OFF)
class JapaneseCompositionQualityTest {
    private lateinit var service: AzooKeyInputMethodService

    @Before fun setUp() {
        service = Robolectric.buildService(AzooKeyInputMethodService::class.java).create().get()
        val state = JSONObject().put("settings", JSONObject()
            .put("enable_zenzai", false).put("live_conversion", true))
            .put("learning", JSONObject()).put("userDictionary", JSONArray())
        service.getSharedPreferences(MainActivity.PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit().putString(MainActivity.STATE_KEY, state.toString()).commit()
        service.onCreateInputView()
        ReflectionHelpers.setField(service, "mode", "japanese")
        ReflectionHelpers.setField(service, "layout", "flick")
    }

    @Test fun noLearningIsNeededToPreferTheCorrectSpellingInTheActualService() {
        for ((reading, natural, mixed) in listOf(
            Triple("おとした", "落とした", "落としタ"),
            Triple("ますこっと", "マスコット", "真スコット"),
            Triple("ぱすたに", "パスタに", "パスタ煮"),
            Triple("ぱすたにちーずをかける", "パスタにチーズをかける", "パスタ煮チーズをかける"),
            Triple("きのうすまほをおとしたからがめんがわれてしまった",
                "昨日スマホを落としたから画面が割れてしまった",
                "昨日スマホを落としタから画面が割れてしまっタ"),
        )) {
            val official = DictionaryCandidates(listOf(mixed, natural), emptyList(), canonicalConversion = natural)
            val candidates = buildCandidates(reading, official)
            assertEquals(reading, natural, candidates.first())
        }
    }

    @Test fun aRegisteredVerbStemDoesNotHideItsParsedAuxiliary() {
        val state = ReflectionHelpers.getField<JSONObject>(service, "state")
        for (includeEnding in listOf(false, true)) {
            val words = JSONArray().put(JSONObject().put("ruby", "いって").put("word", "言って"))
            if (includeEnding) words.put(JSONObject().put("ruby", "た").put("word", "た"))
            state.put("userDictionary", words)
            val candidates = buildCandidates("いってきた", verbCandidates())
            assertTrue("言ってきた" in candidates)
            assertTrue("行ってきた" in candidates)
            assertFalse("言ってきた" in ReflectionHelpers.getField<Set<String>>(service, "candidatePartialTexts"))
            assertFalse("言ってきた" in ReflectionHelpers.getField<Set<String>>(
                service, "candidateNormalizedIncompleteCombinationTexts"))
        }
    }

    @Test fun aLearnedVerbStemAndEndingCannotRemoveTheCompleteVerb() {
        ReflectionHelpers.getField<JSONObject>(service, "state").put("learning", JSONObject()
            .put("いって\t言って", 4).put("た\tた", 4))
        assertTrue("言ってきた" in buildCandidates("いってきた", verbCandidates()))
    }

    @Test fun theDisplayedAlternativeCanBeTappedAndCommittedAsWritten() {
        val commits = mutableListOf<String>()
        val connection = Proxy.newProxyInstance(InputConnection::class.java.classLoader,
            arrayOf(InputConnection::class.java)) { _, method, arguments ->
            if (method.name == "commitText") commits.add(arguments[0].toString())
            when (method.returnType) {
                Boolean::class.javaPrimitiveType -> true
                Int::class.javaPrimitiveType -> 0
                else -> null
            }
        } as InputConnection
        ReflectionHelpers.setField(service, "mStartedInputConnection", connection)
        val candidates = buildCandidates("いってきた", verbCandidates())
        ReflectionHelpers.setField(service, "candidates", candidates.toMutableList())
        ReflectionHelpers.callInstanceMethod<Unit>(service, "renderCandidateValues")
        val row = ReflectionHelpers.getField<LinearLayout>(service, "candidateRow")
        val button = (0 until row.childCount).mapNotNull { row.getChildAt(it) as? TextView }
            .single { it.text.toString() == "言ってきた" }
        assertTrue(button.performClick())
        assertEquals(listOf("言ってきた"), commits)
    }

    private fun verbCandidates() = DictionaryCandidates(
        listOf("行ってきた", "言ってきた"), emptyList(),
        parsedInflectionConversions = setOf("行ってきた", "言ってきた"),
    )

    private fun buildCandidates(reading: String, official: DictionaryCandidates): List<String> {
        ReflectionHelpers.setField(service, "composing", reading)
        val build = AzooKeyInputMethodService::class.java.getDeclaredMethod(
            "buildCandidates", DictionaryCandidates::class.java, Function1::class.java,
        ).apply { isAccessible = true }
        @Suppress("UNCHECKED_CAST")
        return build.invoke(service, official, null) as List<String>
    }
}
