package io.github.StupidGame.azookey_flutter.conversion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveConversionPreviewTest {
    @Test fun longCompositionKeepsAdvancingWhenEveryLookupFinishesAfterMoreInput() {
        val preview = LiveConversionPreview()
        val phrase = "わたしはきょうとうきょうのえきでともだちとあいました"
        val converted = "私は今日東京の駅で友達と会いました"
        val chunk = phrase + "そして"
        val convertedChunk = converted + "そして"
        preview.updateReading(phrase)
        val session = preview.session
        for (count in 1..5) {
            val reading = chunk.repeat(count) + phrase.take(10)
            preview.updateReading(reading)
            assertTrue(preview.remember(session, chunk.repeat(count), convertedChunk.repeat(count)))
            val live = pendingLiveConversionCandidates(
                reading, listOf(reading), preview.preview(reading), emptySet(), emptySet(),
            )
            assertEquals(convertedChunk.repeat(count) + phrase.take(10), live.first())
            assertEquals(reading, live.last())
        }
    }

    @Test fun keepsConvertedTextWhenTypingContinuesBeforeTheNextLookupFinishes() {
        val preview = LiveConversionPreview()
        preview.updateReading("きょうはいいてんき")
        preview.remember(preview.session, "きょうはいいてんき", "今日はいい天気")
        preview.updateReading("きょうはいいてんきなので")
        assertEquals("今日はいい天気なので", preview.preview("きょうはいいてんきなので"))
        preview.updateReading("きょうはいいてんきなのでとうきょうへ")
        assertEquals("今日はいい天気なのでとうきょうへ", preview.preview("きょうはいいてんきなのでとうきょうへ"))
    }

    @Test fun romanInputRetainsTheStablePrefixWhenAnUnfinishedSyllableChanges() {
        val preview = LiveConversionPreview()
        preview.updateReading("とうきょう", "toukyou")
        val session = preview.session
        preview.remember(session, "とうきょう", "東京")
        for ((reading, input) in listOf(
            "とうきょうk" to "toukyouk", "とうきょうか" to "toukyouka",
            "とうきょうかん" to "toukyoukan", "とうきょうかな" to "toukyoukana",
        )) {
            preview.updateReading(reading, input)
            assertEquals("東京" + reading.removePrefix("とうきょう"), preview.preview(reading))
        }
        assertFalse(preview.remember(session, "とうきょうk", "東京k"))
        preview.updateReading("とうきょうかん", "toukyoukan")
        assertNull(preview.preview("とうきょうかん"))
        assertFalse(preview.remember(session, "とうきょう", "東京"))
    }

    @Test fun aLookupCompletedDuringContinuousTypingStillConvertsItsPrefix() {
        val preview = LiveConversionPreview()
        preview.updateReading("きょうはいいてんき")
        val requestSession = preview.session
        preview.updateReading("きょうはいいてんきなので")
        preview.updateReading("きょうはいいてんきなのでさんぽする")
        assertTrue(preview.remember(requestSession, "きょうはいいてんき", "今日はいい天気"))
        assertEquals("今日はいい天気なのでさんぽする", preview.preview("きょうはいいてんきなのでさんぽする"))
        assertTrue(preview.remember(requestSession, "きょうはいいてんきなので", "今日はいい天気なので"))
        assertEquals("今日はいい天気なのでさんぽする", preview.preview("きょうはいいてんきなのでさんぽする"))
    }

    @Test fun anOlderShorterLookupCannotUndoNewerConversion() {
        val preview = LiveConversionPreview()
        val reading = "きょうはいいてんきなのでとうきょうへ"
        preview.updateReading(reading)
        assertTrue(preview.remember(preview.session, reading, "今日はいい天気なので東京へ"))
        assertFalse(preview.remember(preview.session, "きょう", "今日"))
        assertEquals("今日はいい天気なので東京へ", preview.preview(reading))
    }

    @Test fun editingOrDeletingInvalidatesOlderLookupsEvenAfterReturningToTheSameReading() {
        for (edited in listOf("きょ", "きょうと", "")) {
            val preview = LiveConversionPreview()
            preview.updateReading("きょうはいいてんき")
            val oldSession = preview.session
            preview.remember(oldSession, "きょうはいいてんき", "今日はいい天気")
            preview.updateReading(edited)
            assertNull(preview.preview(edited))
            preview.updateReading("きょうはいいてんきなので")
            assertFalse(preview.remember(oldSession, "きょうはいいてんき", "今日はいい天気"))
            assertNull(preview.preview("きょうはいいてんきなので"))
        }
    }

    @Test fun committingOrSwitchingInputFieldsStartsANewSession() {
        val preview = LiveConversionPreview()
        preview.updateReading("とうきょう")
        val oldSession = preview.session
        preview.reset()
        preview.updateReading("とうきょう")
        assertFalse(preview.remember(oldSession, "とうきょう", "東京"))
        assertNull(preview.preview("とうきょう"))
    }

    @Test fun newerModelOrLiteralResultsReplaceTheDictionarySnapshot() {
        val preview = LiveConversionPreview()
        preview.updateReading("きょう")
        preview.remember(preview.session, "きょう", "今日")
        preview.remember(preview.session, "きょう", "京")
        assertEquals("京", preview.preview("きょう"))
        preview.remember(preview.session, "きょう", "きょう")
        preview.updateReading("きょうは")
        assertEquals("きょうは", preview.preview("きょうは"))
        assertFalse(preview.remember(preview.session, "きょうは", ""))
        assertNull(preview.preview("きょうはあ"))
    }

    @Test fun temporaryPrefixOnlyReplacesRawOrPartialCandidates() {
        val reading = "とうきょうにいきます"
        val converted = "東京にいきます"
        for (base in listOf(listOf(reading), listOf("トウキョウニイキマス"),
            listOf("ﾄｳｷｮｳﾆｲｷﾏｽ"), listOf("登録にいきます", reading))) {
            assertEquals(converted, pendingLiveConversionCandidates(
                reading, base, converted, emptySet(), setOf("登録にいきます"),
            ).first())
        }
        for (complete in listOf("東京に行きます", "登録した全文", "2026/10/17")) {
            val base = listOf(complete, reading)
            assertEquals(base, pendingLiveConversionCandidates(reading, base, converted, emptySet(), emptySet()))
        }
        val base = listOf(reading)
        assertEquals(base, pendingLiveConversionCandidates(
            reading, base, converted, emptySet(), emptySet(), exactRegistrationTexts = setOf(reading),
        ))
        assertEquals(base, pendingLiveConversionCandidates(reading, base, null, emptySet(), emptySet()))
        assertEquals(base, pendingLiveConversionCandidates(reading, base, reading, emptySet(), emptySet()))
    }

    @Test fun longerPredictionsNeverSupplyTheTemporaryLiveText() {
        val reading = "とうきょうに"
        val result = pendingLiveConversionCandidates(
            reading, listOf("東京に行きます", reading), "東京に",
            setOf("東京に行きます"), emptySet(),
        )
        assertEquals(listOf("東京に", "東京に行きます", reading), result)
        assertEquals(0, firstCompleteJapaneseCandidateIndex(result, mapOf("東京に行きます" to "とうきょうにいきます")))
    }
}
