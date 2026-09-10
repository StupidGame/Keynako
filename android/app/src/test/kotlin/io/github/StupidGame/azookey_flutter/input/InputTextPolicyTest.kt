package io.github.StupidGame.azookey_flutter.input

import org.junit.Assert.assertEquals
import org.junit.Test

class InputTextPolicyTest {
    @Test
    fun punctuationFollowsTheActiveInputMode() {
        assertEquals("本文？！", punctuationForInputMode("本文?!", "japanese"))
        assertEquals("Really?!", punctuationForInputMode("Really？！", "english"))
        assertEquals("?!", punctuationForInputMode("?!", "symbols"))
    }

    @Test
    fun openingDelimitersResolveToTheirClosingPartner() {
        assertEquals(
            mapOf(
                "「" to "」",
                "『" to "』",
                "(" to ")",
                "（" to "）",
                "[" to "]",
                "［" to "］",
                "{" to "}",
                "｛" to "｝",
                "【" to "】",
                "〈" to "〉",
                "《" to "》",
            ),
            listOf("「", "『", "(", "（", "[", "［", "{", "｛", "【", "〈", "《")
                .associateWith(::closingDelimiterFor),
        )
        assertEquals(null, closingDelimiterFor("本文("))
        assertEquals(null, closingDelimiterFor("」"))
    }
}
