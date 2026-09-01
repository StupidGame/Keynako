package io.github.StupidGame.azookey_flutter

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

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
    private const val LEGACY_WRONG_CONVERSION_ENDPOINT =
        "https://docs.google.com/forms/d/e/1FAIpQLSfpYQqbX8u5SgGVfXjNzCPtKAH_5Mp7PCkUiCiUceEaevb8pQ/formResponse"
    private const val MAXIMUM_RESPONSE_BYTES = 64 * 1024

    fun submitSharedConversionImprovement(
        endpoint: String,
        report: WrongConversionReport,
        appVersion: String,
        completion: (Boolean) -> Unit,
    ) {
        Thread {
            completion(
                try {
                    val url = URL(endpoint.trim())
                    require(url.protocol == "https" && url.host.isNotBlank())
                    val body = JSONObject(sharedConversionImprovementPayload(report, appVersion))
                        .toString()
                    val connection = (url.openConnection() as HttpURLConnection).apply {
                        requestMethod = "POST"
                        connectTimeout = 15_000
                        readTimeout = 30_000
                        doOutput = true
                        instanceFollowRedirects = true
                        setRequestProperty("Content-Type", "application/json; charset=utf-8")
                        setRequestProperty("Accept", "application/json")
                        setRequestProperty("User-Agent", "Keynako $appVersion")
                    }
                    try {
                        connection.outputStream.use { it.write(body.toByteArray(StandardCharsets.UTF_8)) }
                        val status = connection.responseCode
                        val stream = if (status >= 400) connection.errorStream else connection.inputStream
                        val bytes = stream?.use { it.readNBytes(MAXIMUM_RESPONSE_BYTES + 1) } ?: byteArrayOf()
                        status in 200..299 &&
                            bytes.size <= MAXIMUM_RESPONSE_BYTES &&
                            responseAcceptsSubmission(String(bytes, StandardCharsets.UTF_8))
                    } finally {
                        connection.disconnect()
                    }
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

    internal fun sharedConversionImprovementPayload(
        report: WrongConversionReport,
        appVersion: String,
    ): Map<String, Any> = linkedMapOf(
        "word" to report.selected.trim(),
        "ruby" to report.reading.trim(),
        "importance" to 3,
        "categories" to emptyList<String>(),
        "note" to "IME候補改善: 第${report.selectedIndex + 1}候補を選択",
        "source" to "Keynako IME",
        "app_version" to appVersion,
    )

    private fun responseAcceptsSubmission(body: String): Boolean {
        if (body.isBlank()) return true
        return try {
            val response = JSONObject(body)
            !response.has("ok") || response.optBoolean("ok", true)
        } catch (_: Exception) {
            false
        }
    }

    private fun formEncode(entries: List<Pair<String, String>>): String = entries.joinToString("&") { (key, value) ->
        "${URLEncoder.encode(key, StandardCharsets.UTF_8.name())}=${URLEncoder.encode(value, StandardCharsets.UTF_8.name())}"
    }

}
