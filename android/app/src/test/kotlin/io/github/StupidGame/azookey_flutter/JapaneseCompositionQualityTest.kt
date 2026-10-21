package io.github.StupidGame.azookey_flutter

import android.content.Context
import io.github.StupidGame.azookey_flutter.conversion.DictionaryCandidates
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
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
            Triple("きのうすまほをおとしたからがめんがわれてしまった",
                "昨日スマホを落としたから画面が割れてしまった",
                "昨日スマホを落としタから画面が割れてしまっタ"),
        )) {
            ReflectionHelpers.setField(service, "composing", reading)
            val official = DictionaryCandidates(listOf(mixed, natural), emptyList(), canonicalConversion = natural)
            val build = AzooKeyInputMethodService::class.java.getDeclaredMethod(
                "buildCandidates", DictionaryCandidates::class.java, Function1::class.java,
            ).apply { isAccessible = true }
            @Suppress("UNCHECKED_CAST")
            val candidates = build.invoke(service, official, null) as List<String>
            assertEquals(reading, natural, candidates.first())
        }
    }
}
