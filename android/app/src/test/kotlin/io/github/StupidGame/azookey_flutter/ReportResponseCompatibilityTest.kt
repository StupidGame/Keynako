package io.github.StupidGame.azookey_flutter

import java.io.ByteArrayInputStream
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.ConscryptMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
@ConscryptMode(ConscryptMode.Mode.OFF)
class ReportResponseCompatibilityTest {
    @Test fun parsesResponsesOnAndroidBeforeReadNBytesWasIntroduced() {
        assertTrue(accepts("{\"ok\":true}"))
        assertTrue(accepts(""))
        assertFalse(accepts("{\"ok\":false}"))
        assertFalse(accepts("<html>error</html>"))
        assertTrue(accepts(" ".repeat(64 * 1024)))
        assertFalse(accepts(" ".repeat(64 * 1024 + 1)))
    }

    private fun accepts(value: String) = ReportClient.acceptsSharedSubmissionBody(
        ByteArrayInputStream(value.toByteArray(Charsets.UTF_8)),
    )
}
