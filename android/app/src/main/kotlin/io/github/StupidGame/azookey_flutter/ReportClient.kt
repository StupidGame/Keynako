package io.github.StupidGame.azookey_flutter

import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

data class WrongConversionReport(
    val suggested: String,
    val selected: String,
    val selectedIndex: Int,
    val reading: String,
    val rawInput: String,
    val inputStyle: String,
    val leftContext: String,
    val rightContext: String,
    val japaneseLayout: String,
    val textContentType: String,
    val returnKeyType: String,
)

object ReportClient {
    // These wrong-conversion endpoints and entry IDs match the Swift app.
    private const val SUGGESTION_ENDPOINT =
        "https://docs.google.com/forms/d/e/1FAIpQLSeTdOtFZfuFHurrDMIIzLyX-Z84Y3IKHflewNZ8dPOFgCTOtw/formResponse"
    private const val REPORT_TYPE_ENTRY = "entry.1715004013"
    private const val PAYLOAD_ENTRY = "entry.562739847"
    private const val LEGACY_WRONG_CONVERSION_ENDPOINT =
        "https://docs.google.com/forms/d/e/1FAIpQLSfpYQqbX8u5SgGVfXjNzCPtKAH_5Mp7PCkUiCiUceEaevb8pQ/formResponse"

    fun submit(
        report: WrongConversionReport,
        settings: JSONObject,
        appVersion: String,
        osVersion: String,
        completion: (Boolean) -> Unit,
    ) {
        Thread {
            completion(
                try {
                    val payload = payload(report, settings, appVersion, osVersion).toString()
                    val body = formEncode(
                        listOf(
                            REPORT_TYPE_ENTRY to "non_first_candidate_selection_report",
                            PAYLOAD_ENTRY to payload,
                        ),
                    )
                    val connection = (URL(SUGGESTION_ENDPOINT).openConnection() as HttpURLConnection).apply {
                        requestMethod = "POST"
                        connectTimeout = 15_000
                        readTimeout = 15_000
                        doOutput = true
                        setRequestProperty("mode", "no-cors")
                        setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                    }
                    connection.outputStream.use { it.write(body.toByteArray(StandardCharsets.UTF_8)) }
                    val status = connection.responseCode
                    connection.disconnect()
                    status in 200..399
                } catch (_: Exception) {
                    false
                },
            )
        }.start()
    }

    fun submitLegacyWrongConversion(
        candidate: String,
        ruby: String,
        index: Int,
        appVersion: String,
        learningEnabled: Boolean,
        completion: (Boolean) -> Unit,
    ) {
        Thread {
            completion(
                try {
                    val body = formEncode(
                        listOf(
                            "entry.134904003" to candidate,
                            "entry.869464972" to ruby,
                            "entry.1459534202" to index.toString(),
                            "entry.571429448" to appVersion,
                            "entry.524189292" to if (learningEnabled) "有効" else "無効",
                        ),
                    )
                    val connection = (URL(LEGACY_WRONG_CONVERSION_ENDPOINT).openConnection() as HttpURLConnection).apply {
                        requestMethod = "POST"
                        connectTimeout = 15_000
                        readTimeout = 15_000
                        doOutput = true
                        setRequestProperty("mode", "no-cors")
                        setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                    }
                    connection.outputStream.use { it.write(body.toByteArray(StandardCharsets.UTF_8)) }
                    val status = connection.responseCode
                    connection.disconnect()
                    status in 200..399
                } catch (_: Exception) {
                    false
                },
            )
        }.start()
    }

    private fun payload(
        report: WrongConversionReport,
        settings: JSONObject,
        appVersion: String,
        osVersion: String,
    ): JSONObject {
        val input = JSONObject().apply {
            put("text", report.reading)
            put(
                "segments",
                JSONArray().put(
                    JSONObject().apply {
                        put("value", report.rawInput)
                        put("inputStyle", report.inputStyle)
                    },
                ),
            )
        }
        return JSONObject().apply {
            put("suggested", report.suggested)
            put("selected", report.selected)
            put("selectedIndex", report.selectedIndex.toString())
            put("input", input)
            if (settings.optBoolean("wrong_conversion_include_context", false)) {
                if (report.leftContext.isNotBlank()) put("leftSideContext", report.leftContext.takeLast(10))
                if (report.rightContext.isNotBlank()) put("rightSideContext", report.rightContext.take(10))
            }
            val nickname = settings.optString("wrong_conversion_report_user_nickname", "").trim()
            if (nickname.isNotEmpty()) put("userNickname", nickname)
            put("appVersion", appVersion)
            put("osVersion", osVersion)
            put("zenzaiEnabled", settings.optBoolean("enable_zenzai", false).toString())
            put(
                "zenzaiEffort",
                when (settings.optInt("zenzai_effort", 1)) {
                    0 -> "low"
                    2 -> "high"
                    else -> "medium"
                },
            )
            put("japaneseLayout", report.japaneseLayout)
            put("textContentType", report.textContentType)
            put("returnKeyType", report.returnKeyType)
            put("date", iso8601Now())
        }
    }

    private fun formEncode(entries: List<Pair<String, String>>): String = entries.joinToString("&") { (key, value) ->
        "${URLEncoder.encode(key, StandardCharsets.UTF_8.name())}=${URLEncoder.encode(value, StandardCharsets.UTF_8.name())}"
    }

    private fun iso8601Now(): String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }.format(Date())
}
