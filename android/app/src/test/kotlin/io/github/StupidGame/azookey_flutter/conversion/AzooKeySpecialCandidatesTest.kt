package io.github.StupidGame.azookey_flutter.conversion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AzooKeySpecialCandidatesTest {
    @Test
    fun matchesOriginalNumberAndTimeExamples() {
        assertTrue("49,000" in AzooKeySpecialCandidates.complete("49000"))
        assertTrue("2,129.49" in AzooKeySpecialCandidates.complete("2129.49"))
        assertTrue("-13,932" in AzooKeySpecialCandidates.complete("-13932"))
        assertTrue("1:23" in AzooKeySpecialCandidates.complete("123"))
        assertTrue("12:34" in AzooKeySpecialCandidates.complete("1234"))
        assertFalse("12:60" in AzooKeySpecialCandidates.complete("1260"))
    }

    @Test
    fun completesEmailAndEraCandidates() {
        assertTrue("azooKey@gmail.com" in AzooKeySpecialCandidates.emails("azooKey@g"))
        assertFalse("azooKey@yahoo.co.jp" in AzooKeySpecialCandidates.emails("azooKey@g"))
        assertEquals(emptyList<String>(), AzooKeySpecialCandidates.emails("あずき@"))
        assertTrue("令和元年" in AzooKeySpecialCandidates.complete("2019ねん"))
        assertTrue("2019年" in AzooKeySpecialCandidates.complete("れいわがんねん"))
    }
}
