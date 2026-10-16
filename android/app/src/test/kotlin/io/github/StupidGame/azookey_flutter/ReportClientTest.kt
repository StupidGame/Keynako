package io.github.StupidGame.azookey_flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test
import java.net.URL

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
            appVersion = "3.1.0",
        )

        assertEquals("小倉", payload["word"])
        assertEquals("おぐら", payload["ruby"])
        assertEquals(3, payload["importance"])
        assertEquals(emptyList<String>(), payload["categories"])
        assertEquals("IME候補改善: 第2候補を選択", payload["note"])
        assertEquals("Keynako IME", payload["source"])
        assertEquals("3.1.0", payload["app_version"])
        assertFalse(payload.containsKey("leftContext"))
        assertFalse(payload.containsKey("rightContext"))
        assertFalse(payload.values.contains("小椋"))
    }

    @Test
    fun onlyAppsScriptResponseRedirectIsAccepted() {
        val endpoint = URL("https://script.google.com/macros/s/deployment/exec")
        assertEquals(
            "https://script.googleusercontent.com/macros/echo?token=1",
            ReportClient.sharedSubmissionResponseUrl(
                endpoint, 302, "https://script.googleusercontent.com/macros/echo?token=1",
            )?.toString(),
        )
        assertNull(ReportClient.sharedSubmissionResponseUrl(endpoint, 302, "https://example.com/collect"))
        assertNull(ReportClient.sharedSubmissionResponseUrl(endpoint, 307, "https://script.googleusercontent.com/"))
    }
}
