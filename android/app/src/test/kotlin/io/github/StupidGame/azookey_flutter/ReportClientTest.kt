package io.github.StupidGame.azookey_flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class ReportClientTest {
    @Test
    fun sharedConversionImprovementUsesDictionarySubmissionShape() {
        val payload = ReportClient.sharedConversionImprovementPayload(
            report = WrongConversionReport(
                suggested = "小椋",
                selected = "小倉",
                selectedIndex = 1,
                reading = "おぐら",
                rawInput = "ogura",
                inputStyle = "roman2kana",
                leftContext = "秘密の前文",
                rightContext = "秘密の後文",
                japaneseLayout = "qwerty",
                textContentType = "1",
                returnKeyType = "default",
            ),
            appVersion = "3.0.1",
        )

        assertEquals("小倉", payload["word"])
        assertEquals("おぐら", payload["ruby"])
        assertEquals(3, payload["importance"])
        assertEquals(emptyList<String>(), payload["categories"])
        assertEquals("IME候補改善: 第2候補を選択", payload["note"])
        assertEquals("Keynako IME", payload["source"])
        assertEquals("3.0.1", payload["app_version"])
        assertFalse(payload.containsKey("leftContext"))
        assertFalse(payload.containsKey("rightContext"))
        assertFalse(payload.values.contains("小椋"))
    }
}
