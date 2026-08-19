package io.github.StupidGame.azookey_flutter

import android.content.ClipboardManager
import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.inputmethodservice.InputMethodService
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.TextView
import com.kazumaproject.zenz.ZenzEngine
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.text.Normalizer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs
import kotlin.random.Random

class AzooKeyInputMethodService : InputMethodService() {
    private lateinit var root: LinearLayout
    private lateinit var candidateRow: LinearLayout
    private lateinit var keyboardContainer: LinearLayout
    private var state = JSONObject()
    private var settings = JSONObject()
    private var composing = ""
    private var rawRoman = ""
    private var mode = "japanese"
    private var layout = "flick"
    private var shift = false
    private var capsLock = false
    private var selectedCandidate = 0
    private var activeCustomTab: String? = null
    private var candidates = mutableListOf<String>()
    private var pendingReport: WrongConversionReport? = null
    private var palette = KeyboardPalette.default()
    private val zenzaiRuntime by lazy { AndroidZenzaiRuntime(this) }

    override fun onDestroy() {
        if (this::root.isInitialized) zenzaiRuntime.close()
        super.onDestroy()
    }

    override fun onCreateInputView(): View {
        reloadState()
        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(palette.background)
        }
        val candidateScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            candidateRow = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            addView(candidateRow)
        }
        root.addView(
            candidateScroll,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(43)),
        )
        keyboardContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        root.addView(
            keyboardContainer,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT),
        )
        renderCandidates()
        renderKeyboard()
        prepareZenzaiIfNeeded()
        return root
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        if (::root.isInitialized && settings.optBoolean("enable_zenzai", false)) {
            zenzaiRuntime.cancel()
        }
        reloadState()
        composing = ""
        rawRoman = ""
        selectedCandidate = 0
        activeCustomTab = null
        mode = when (info?.inputType?.and(0x0000000f)) {
            0x00000002, 0x00000003 -> "symbols"
            else -> "japanese"
        }
        layout = if (mode == "japanese") {
            settings.optString("keyboard_type", "flick")
        } else {
            "qwerty"
        }
        if (::root.isInitialized) {
            root.setBackgroundColor(palette.background)
            renderCandidates()
            renderKeyboard()
            prepareZenzaiIfNeeded()
        }
    }

    private fun reloadState() {
        val value = getSharedPreferences(
            MainActivity.PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        ).getString(MainActivity.STATE_KEY, null)
        state = try {
            if (value.isNullOrBlank()) JSONObject() else JSONObject(value)
        } catch (_: Exception) {
            JSONObject()
        }
        settings = state.optJSONObject("settings") ?: JSONObject()
        if (settings.has("memory_reset_setting") && settings.opt("memory_reset_setting") != false) {
            state.put("learning", JSONObject())
            settings.put("memory_reset_setting", false)
            state.put("settings", settings)
            persistState()
        }
        palette = loadPalette()
    }

    private fun loadPalette(): KeyboardPalette {
        val night = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
            Configuration.UI_MODE_NIGHT_YES
        val selectedId = state.optString(
            if (night) "darkThemeId" else "lightThemeId",
            if (night) "midnight" else "classic",
        )
        val themes = state.optJSONArray("themes") ?: return KeyboardPalette.default(night)
        for (index in 0 until themes.length()) {
            val theme = themes.optJSONObject(index) ?: continue
            if (theme.optString("id") == selectedId) {
                return KeyboardPalette(
                    background = theme.optLong("backgroundColor", 0xffd1d5dbL).toInt(),
                    key = theme.optLong("keyColor", 0xffffffffL).toInt(),
                    special = theme.optLong("specialKeyColor", 0xffadb5bdL).toInt(),
                    text = theme.optLong("textColor", 0xff111827L).toInt(),
                    accent = theme.optLong("accentColor", 0xff2563ebL).toInt(),
                )
            }
        }
        return KeyboardPalette.default(night)
    }

    private fun renderKeyboard() {
        keyboardContainer.removeAllViews()
        val heightScale = settings.optDouble("keyboard_height_scale", 1.0).coerceIn(0.7, 1.4)
        when {
            activeCustomTab != null -> renderCustomTab(activeCustomTab!!, heightScale)
            mode == "symbols" -> renderSymbols(heightScale)
            layout == "qwerty" -> renderQwerty(heightScale)
            else -> renderFlick(heightScale)
        }
        if (activeCustomTab == null) renderStandaloneCustomKeys(heightScale)
    }

    private fun renderFlick(scale: Double) {
        val keys = if (mode == "english") listOf(
            listOf(
                FlickKey("@#/&_", "@", "#", "/", "&", "_"),
                FlickKey("ABC", "a", "b", "c", "2", null),
                FlickKey("DEF", "d", "e", "f", "3", null),
                FlickKey("⌫", action = "delete", special = true),
            ),
            listOf(
                FlickKey("GHI", "g", "h", "i", "4", null),
                FlickKey("JKL", "j", "k", "l", "5", null),
                FlickKey("MNO", "m", "n", "o", "6", null),
                FlickKey("空白", action = "space", special = true),
            ),
            listOf(
                FlickKey("PQRS", "p", "q", "r", "s", "7"),
                FlickKey("TUV", "t", "u", "v", "8", null),
                FlickKey("WXYZ", "w", "x", "y", "z", "9"),
                FlickKey("改行", action = "enter", special = true),
            ),
            listOf(
                FlickKey("☆123", action = "symbols", special = true),
                FlickKey(if (shift || capsLock) "A/a" else "a/A", action = "shiftEnglish", special = true),
                FlickKey(".,?!", ".", ",", "?", "!", "'"),
                FlickKey("🌐", action = "nextKeyboard", special = true),
            ),
        ) else listOf(
            listOf(
                FlickKey("あ", "あ", "い", "う", "え", "お"),
                FlickKey("か", "か", "き", "く", "け", "こ"),
                FlickKey("さ", "さ", "し", "す", "せ", "そ"),
                FlickKey("⌫", action = "delete", special = true),
            ),
            listOf(
                FlickKey("た", "た", "ち", "つ", "て", "と"),
                FlickKey("な", "な", "に", "ぬ", "ね", "の"),
                FlickKey("は", "は", "ひ", "ふ", "へ", "ほ"),
                FlickKey("空白", action = "space", special = true),
            ),
            listOf(
                FlickKey("ま", "ま", "み", "む", "め", "も"),
                FlickKey("や", "や", "「", "ゆ", "」", "よ"),
                FlickKey("ら", "ら", "り", "る", "れ", "ろ"),
                FlickKey("改行", action = "enter", special = true),
            ),
            listOf(
                FlickKey("☆123", action = "symbols", special = true),
                FlickKey("小ﾞﾟ", action = "kogana", special = true),
                FlickKey("わ", "わ", "を", "ん", "ー", "〜"),
                FlickKey("🌐", action = "nextKeyboard", special = true),
            ),
        )
        for (row in keys) {
            val rowView = newRow(scale)
            for (key in row) rowView.addView(createFlickKey(key, scale), weightParams())
            keyboardContainer.addView(rowView)
        }
    }

    private fun renderQwerty(scale: Double) {
        val rows = listOf("qwertyuiop", "asdfghjkl", "zxcvbnm")
        for ((rowIndex, letters) in rows.withIndex()) {
            val row = newRow(scale)
            if (rowIndex == 2) {
                row.addView(
                    createKey(if (capsLock) "⇪" else "⇧", true, scale) { toggleShift() },
                    weightParams(1.4f),
                )
            }
            for (letter in letters) {
                val label = if (shift || capsLock) letter.uppercase() else letter.toString()
                row.addView(createKey(label, false, scale) { inputText(label) }, weightParams())
            }
            if (rowIndex == 2) {
                row.addView(createKey("⌫", true, scale) { delete() }, weightParams(1.4f))
            }
            keyboardContainer.addView(row)
        }
        val bottom = newRow(scale)
        bottom.addView(createKey("☆123", true, scale) { setMode("symbols") }, weightParams(1.5f))
        bottom.addView(createKey("🌐", true, scale) { nextKeyboard() }, weightParams(1.2f))
        bottom.addView(createKey("space", false, scale) { space() }, weightParams(4f))
        bottom.addView(createKey("return", true, scale) { enter() }, weightParams(2f))
        keyboardContainer.addView(bottom)
    }

    private fun renderSymbols(scale: Double) {
        val rows = listOf(
            listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0"),
            listOf("-", "/", ":", ";", "(", ")", "¥", "&", "@", "\""),
            listOf("。", "、", "？", "！", "…", "・", "〜", "#", "%"),
        )
        for (values in rows) {
            val row = newRow(scale)
            for (value in values) {
                row.addView(createKey(value, false, scale) { directCommit(value) }, weightParams())
            }
            keyboardContainer.addView(row)
        }
        val bottom = newRow(scale)
        bottom.addView(createKey("あいう", true, scale) { setMode("japanese") }, weightParams(1.6f))
        bottom.addView(createKey("ABC", true, scale) { setMode("english") }, weightParams(1.5f))
        bottom.addView(createKey("space", false, scale) { directCommit(" ") }, weightParams(3f))
        bottom.addView(createKey("⌫", true, scale) { delete() }, weightParams(1.3f))
        bottom.addView(createKey("return", true, scale) { enter() }, weightParams(1.8f))
        keyboardContainer.addView(bottom)
    }

    private fun renderCustomTab(id: String, scale: Double) {
        val tabs = state.optJSONArray("customTabs") ?: return setMode("japanese")
        var target: JSONObject? = null
        for (index in 0 until tabs.length()) {
            val tab = tabs.optJSONObject(index) ?: continue
            if (tab.optString("id") == id) target = tab
        }
        if (target == null) return setMode("japanese")
        val columns = target.optInt("columns", 4).coerceIn(1, 8)
        val keys = target.optJSONArray("keys") ?: JSONArray()
        var row = newRow(scale)
        var count = 0
        for (index in 0 until keys.length()) {
            val key = keys.optJSONObject(index) ?: continue
            val label = key.optString("label", "")
            row.addView(createCustomKey(key, scale), weightParams())
            count += 1
            if (count % columns == 0) {
                keyboardContainer.addView(row)
                row = newRow(scale)
            }
        }
        if (row.childCount > 0) {
            while (row.childCount < columns) row.addView(View(this), weightParams())
            keyboardContainer.addView(row)
        }
        val bottom = newRow(scale)
        bottom.addView(createKey("あいう", true, scale) { setMode("japanese") }, weightParams())
        bottom.addView(createKey("⌫", true, scale) { delete() }, weightParams())
        bottom.addView(createKey("space", false, scale) { space() }, weightParams(2f))
        bottom.addView(createKey("return", true, scale) { enter() }, weightParams())
        keyboardContainer.addView(bottom)
    }

    private fun renderStandaloneCustomKeys(scale: Double) {
        val keys = state.optJSONArray("customKeys") ?: return
        if (keys.length() == 0) return
        for (start in 0 until minOf(keys.length(), 8) step 4) {
            val row = newRow(scale)
            for (index in start until minOf(start + 4, keys.length())) {
                val key = keys.optJSONObject(index) ?: continue
                row.addView(createCustomKey(key, scale), weightParams())
            }
            while (row.childCount < 4) row.addView(View(this), weightParams())
            keyboardContainer.addView(row)
        }
    }

    private fun createCustomKey(key: JSONObject, scale: Double): View {
        val view = createKey(key.optString("label", key.optString("name", "")), false, scale, null)
        val handler = Handler(Looper.getMainLooper())
        var startX = 0f
        var startY = 0f
        var longPressed = false
        val longPress = Runnable {
            val action = key.optJSONObject("longPress") ?: return@Runnable
            longPressed = true
            dispatchAction(action)
            feedback(view)
        }
        view.setOnTouchListener { target, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.x
                    startY = event.y
                    longPressed = false
                    target.isPressed = true
                    handler.postDelayed(longPress, 500)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    handler.removeCallbacks(longPress)
                    target.isPressed = false
                    if (!longPressed) {
                        val dx = event.x - startX
                        val dy = event.y - startY
                        val threshold = dp(20).toFloat() *
                            settings.optDouble("flick_sensitivity_setting", 1.0).toFloat()
                        val direction = if (abs(dx) < threshold && abs(dy) < threshold) {
                            "tap"
                        } else if (abs(dx) > abs(dy)) {
                            if (dx < 0) "left" else "right"
                        } else {
                            if (dy < 0) "up" else "down"
                        }
                        dispatchAction(key.optJSONObject(direction) ?: key.optJSONObject("tap"))
                        feedback(target)
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(longPress)
                    target.isPressed = false
                    true
                }
                else -> true
            }
        }
        return view
    }

    private fun createFlickKey(key: FlickKey, scale: Double): View {
        val view = createKey(key.label, key.special, scale, null)
        var startX = 0f
        var startY = 0f
        view.setOnTouchListener { target, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.x
                    startY = event.y
                    target.isPressed = true
                    true
                }
                MotionEvent.ACTION_UP -> {
                    target.isPressed = false
                    val dx = event.x - startX
                    val dy = event.y - startY
                    val threshold = dp(20).toFloat() *
                        settings.optDouble("flick_sensitivity_setting", 1.0).toFloat()
                    val value = if (abs(dx) < threshold && abs(dy) < threshold) {
                        key.center
                    } else if (abs(dx) > abs(dy)) {
                        if (dx < 0) key.left else key.right
                    } else {
                        if (dy < 0) key.up else key.down
                    }
                    if (key.action != null) dispatchNamedAction(key.action) else inputText(value ?: key.center)
                    feedback(target)
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    target.isPressed = false
                    true
                }
                else -> true
            }
        }
        return view
    }

    private fun createKey(
        label: String,
        special: Boolean,
        scale: Double,
        action: (() -> Unit)?,
    ): TextView {
        val textSizeSetting = settings.optDouble("key_view_font_size", -1.0)
        return TextView(this).apply {
            text = label
            gravity = Gravity.CENTER
            setTextColor(palette.text)
            textSize = if (textSizeSetting > 0) textSizeSetting.toFloat() else if (label.length > 3) 11f else 17f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
            isAllCaps = false
            background = roundedDrawable(if (special) palette.special else palette.key, dp(6).toFloat())
            val vertical = (dp(2) * scale).toInt().coerceAtLeast(1)
            val horizontal = dp(2)
            setPadding(horizontal, vertical, horizontal, vertical)
            if (action != null) {
                setOnClickListener {
                    action()
                    feedback(this)
                }
            }
        }
    }

    private fun newRow(scale: Double): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        setPadding(dp(2), dp(2), dp(2), dp(2))
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            (dp(47) * scale).toInt(),
        )
    }

    private fun weightParams(weight: Float = 1f) = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, weight).apply {
        setMargins(dp(2), 0, dp(2), 0)
    }

    private fun renderCandidates(showTabs: Boolean = composing.isEmpty()) {
        if (!::candidateRow.isInitialized) return
        candidateRow.removeAllViews()
        if (showTabs) {
            if (settings.optBoolean("display_tab_bar_button", true)) renderTabBar()
            return
        }
        candidates = buildCandidates().toMutableList()
        if (candidates.isEmpty()) candidates.add(displayReading())
        renderCandidateValues()
    }

    private fun renderCandidateValues() {
        candidateRow.removeAllViews()
        val candidateSize = settings.optDouble("result_view_font_size", -1.0)
        for ((index, candidate) in candidates.withIndex()) {
            candidateRow.addView(TextView(this).apply {
                text = candidate
                gravity = Gravity.CENTER
                setPadding(dp(15), 0, dp(15), 0)
                setTextColor(if (index == selectedCandidate) palette.accent else palette.text)
                textSize = if (candidateSize > 0) candidateSize.toFloat() else 16f
                setOnClickListener { commitCandidate(index) }
                setOnLongClickListener {
                    showLegacyReportPrompt(candidate, index)
                    true
                }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(43)))
        }
    }

    private fun renderTabBar() {
        val values = state.optJSONArray("tabBar") ?: JSONArray(
            listOf("dismiss", "resize", "emoji", "japanese", "english"),
        )
        for (index in 0 until values.length()) {
            val value = values.optString(index)
            val label = when {
                value == "dismiss" -> "⌄"
                value == "resize" -> "↔"
                value == "emoji" -> "😊"
                value == "japanese" -> "あいう"
                value == "english" -> "ABC"
                value == "clipboard" -> "📋"
                value.startsWith("custom:") -> customTabName(value.removePrefix("custom:"))
                else -> value
            }
            candidateRow.addView(TextView(this).apply {
                text = label
                gravity = Gravity.CENTER
                setTextColor(palette.text)
                setPadding(dp(16), 0, dp(16), 0)
                setOnClickListener { selectTab(value) }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(43)))
        }
        if (settings.optBoolean("enable_clipboard_history_manager_tab", false) &&
            (0 until values.length()).none { values.optString(it) == "clipboard" }
        ) {
            candidateRow.addView(TextView(this).apply {
                text = "📋"
                gravity = Gravity.CENTER
                setPadding(dp(16), 0, dp(16), 0)
                setOnClickListener { showClipboardHistory() }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(43)))
        }
    }

    private fun selectTab(value: String) {
        when {
            value == "dismiss" -> requestHideSelf(0)
            value == "emoji" -> showEmoji()
            value == "japanese" -> setMode("japanese")
            value == "english" -> setMode("english")
            value == "clipboard" -> showClipboardHistory()
            value.startsWith("custom:") -> {
                activeCustomTab = value.removePrefix("custom:")
                renderKeyboard()
            }
            value == "resize" -> Unit
        }
    }

    private fun customTabName(id: String): String {
        val tabs = state.optJSONArray("customTabs") ?: return "タブ"
        for (index in 0 until tabs.length()) {
            val tab = tabs.optJSONObject(index) ?: continue
            if (tab.optString("id") == id) return tab.optString("name", "タブ")
        }
        return "タブ"
    }

    private fun showEmoji() {
        candidateRow.removeAllViews()
        val emoji = listOf("😀", "😃", "😊", "😂", "🥰", "😍", "😭", "😡", "👍", "🙏", "❤️", "🎉", "✨", "⭐️")
        for (value in emoji) addCandidateButton(value) { directCommit(value) }
    }

    private fun showClipboardHistory() {
        candidateRow.removeAllViews()
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        val current = clipboard.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString()
        val history = mutableListOf<String>()
        if (!current.isNullOrBlank()) history.add(current)
        val stored = state.optJSONArray("clipboardHistory") ?: JSONArray()
        for (index in 0 until stored.length()) {
            val value = stored.optString(index)
            if (value.isNotBlank() && value !in history) history.add(value)
        }
        persistClipboardHistory(history.take(50))
        for (value in history.take(20)) {
            addCandidateButton(value.take(32)) { directCommit(value) }
        }
        if (history.isEmpty()) addCandidateButton("履歴はありません") {}
    }

    private fun persistClipboardHistory(history: List<String>) {
        state.put("clipboardHistory", JSONArray(history))
        getSharedPreferences(MainActivity.PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit().putString(MainActivity.STATE_KEY, state.toString()).apply()
    }

    private fun addCandidateButton(label: String, action: () -> Unit) {
        candidateRow.addView(TextView(this).apply {
            text = label
            gravity = Gravity.CENTER
            setTextColor(palette.text)
            setPadding(dp(15), 0, dp(15), 0)
            setOnClickListener { action() }
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(43)))
    }

    private fun inputText(value: String?) {
        if (value.isNullOrEmpty()) return
        if (mode == "english") {
            directCommit(if (shift || capsLock) value.uppercase(Locale.ROOT) else value)
            if (shift && !capsLock) {
                shift = false
                renderKeyboard()
            }
            return
        }
        if (layout == "qwerty") rawRoman += value.lowercase() else composing += value
        updateComposition()
    }

    private fun updateComposition() {
        val reading = displayReading()
        if (layout == "qwerty") composing = reading
        selectedCandidate = 0
        candidates = buildCandidates().toMutableList()
        if (candidates.isEmpty() && reading.isNotEmpty()) candidates.add(reading)
        val live = settings.optBoolean("live_conversion", true)
        val displayed = if (live && candidates.isNotEmpty()) candidates.first() else reading
        currentInputConnection?.setComposingText(displayed, 1)
        renderCandidateValues()
        requestZenzaiCandidates(reading, candidates.toList())
    }

    private fun requestZenzaiCandidates(reading: String, baseCandidates: List<String>) {
        if (!settings.optBoolean("enable_zenzai", false) || reading.isBlank()) return
        val effort = settings.optInt("zenzai_effort", 1).coerceIn(0, 2)
        val size = if (effort == 0) "xsmall" else "small"
        val leftContext = currentInputConnection
            ?.getTextBeforeCursor(20, 0)
            ?.toString()
            .orEmpty()
        val rightContext = currentInputConnection
            ?.getTextAfterCursor(20, 0)
            ?.toString()
            .orEmpty()
        zenzaiRuntime.rank(
            modelSize = size,
            reading = reading,
            leftContext = leftContext,
            rightContext = rightContext,
            baseCandidates = baseCandidates,
            maxTokens = when (effort) {
                0 -> 24
                2 -> 48
                else -> 32
            },
        ) { ranked ->
            if (displayReading() != reading || ranked.isEmpty()) return@rank
            candidates = ranked.toMutableList()
            selectedCandidate = 0
            if (settings.optBoolean("live_conversion", true)) {
                currentInputConnection?.setComposingText(candidates.first(), 1)
            }
            renderCandidateValues()
        }
    }

    private fun buildCandidates(): List<String> {
        val reading = displayReading()
        if (reading.isEmpty()) return emptyList()
        val values = linkedSetOf<String>()
        val dictionary = state.optJSONArray("userDictionary") ?: JSONArray()
        for (index in 0 until dictionary.length()) {
            val entry = dictionary.optJSONObject(index) ?: continue
            if (entry.optString("ruby") == reading) {
                values.add(
                    if (entry.optBoolean("isTemplateMode", false)) {
                        renderTemplate(entry.optString("formatLiteral", entry.optString("word")))
                    } else {
                        entry.optString("word")
                    },
                )
            }
        }
        systemDictionary[reading]?.let(values::addAll)
        values.add(reading)
        val katakana = hiraganaToKatakana(reading)
        if (katakana != reading) values.add(katakana)
        if (settings.optBoolean("half_kana_candidate", true)) {
            values.add(katakanaToHalfWidth(katakana))
        }
        if (layout == "qwerty" && settings.optBoolean("full_roman_candidate", true) && rawRoman.isNotEmpty()) {
            values.add(asciiToFullWidth(rawRoman))
        }
        if (layout == "qwerty" && settings.optBoolean("unicode_candidate", true)) {
            unicodeCandidate(rawRoman)?.let(values::add)
        }
        if (layout == "qwerty" && settings.optBoolean("typography_roman_candidate", true) && rawRoman.isNotEmpty()) {
            values.add(toMathematicalBold(rawRoman))
        }
        if (settings.optBoolean("emoji_dictionary_enabled", true)) emojiDictionary[reading]?.let(values::addAll)
        if (settings.optBoolean("kaomoji_dictionary_enabled", false)) kaomojiDictionary[reading]?.let(values::addAll)
        if (layout == "qwerty" && settings.optBoolean("roman_english_candidate", true)) values.add(rawRoman)
        val learningMode = settings.optInt("memory_learining_styple_setting", 0)
        val scores = state.optJSONObject("learning") ?: JSONObject()
        return values.filter { it.isNotEmpty() }.withIndex().sortedWith(
            compareByDescending<IndexedValue<String>> {
                if (learningMode == 2) 0 else scores.optInt("$reading\t${it.value}", 0)
            }.thenBy { it.index },
        ).map { it.value }
    }

    private fun commitCandidate(index: Int) {
        if (candidates.isEmpty()) return
        if (settings.optBoolean("enable_zenzai", false)) zenzaiRuntime.cancel()
        val selectedIndex = index.coerceIn(0, candidates.lastIndex)
        val candidate = candidates[selectedIndex]
        learnCandidate(displayReading(), candidate)
        val report = WrongConversionReport(
            suggested = candidates.first(),
            selected = candidate,
            selectedIndex = selectedIndex,
            reading = displayReading(),
            rawInput = if (layout == "qwerty") rawRoman else composing,
            inputStyle = if (layout == "qwerty") "roman2kana" else "direct",
            leftContext = currentInputConnection?.getTextBeforeCursor(10, 0)?.toString().orEmpty(),
            rightContext = currentInputConnection?.getTextAfterCursor(10, 0)?.toString().orEmpty(),
            japaneseLayout = layout,
            textContentType = currentInputEditorInfo?.inputType?.toString() ?: "nil",
            returnKeyType = currentInputEditorInfo?.imeOptions?.and(EditorInfo.IME_MASK_ACTION)?.toString() ?: "default",
        )
        currentInputConnection?.commitText(candidate, 1)
        composing = ""
        rawRoman = ""
        selectedCandidate = 0
        renderCandidates()
        maybeOfferReport(report)
    }

    private fun maybeOfferReport(report: WrongConversionReport) {
        if (!settings.optBoolean("enable_wrong_conversion_report", false)) return
        if (report.selectedIndex == 0 || report.reading.isBlank()) return
        if (!report.reading.matches(Regex("[ぁ-ゖa-zA-Z0-9]+"))) return
        if (report.suggested.startsWith(report.selected) && report.suggested.length > report.selected.length) return
        val denominator = settings.optInt("wrong_conversion_report_frequency", 10).coerceAtLeast(1)
        if (denominator > 1 && Random.nextInt(denominator) != 0) return
        val pairKey = report.reading + "\u001f" + report.selected
        val reported = state.optJSONArray("reportedWrongConversionPairs") ?: JSONArray()
        if ((0 until reported.length()).any { reported.optString(it) == pairKey }) return
        pendingReport = report
        candidateRow.removeAllViews()
        addCandidateButton("「${report.selected}」を選択") {}
        addCandidateButton("改善レポートを送信") { submitPendingReport() }
        addCandidateButton("詳細") { showReportDetails(report) }
        addCandidateButton("×") {
            pendingReport = null
            renderCandidates()
        }
    }

    private fun showReportDetails(report: WrongConversionReport) {
        candidateRow.removeAllViews()
        addCandidateButton("第一候補: ${report.suggested}") {}
        addCandidateButton("選択: ${report.selected}") {}
        addCandidateButton("入力: ${report.reading}") {}
        if (settings.optBoolean("wrong_conversion_include_context", false)) {
            addCandidateButton("前: ${report.leftContext.takeLast(10)}") {}
            addCandidateButton("後: ${report.rightContext.take(10)}") {}
        }
        addCandidateButton("送信") { submitPendingReport() }
        addCandidateButton("戻る") { maybeOfferReportWithoutFiltering(report) }
    }

    private fun showLegacyReportPrompt(candidate: String, index: Int) {
        candidateRow.removeAllViews()
        addCandidateButton("「$candidate」を誤変換として報告") {}
        addCandidateButton("送信") {
            candidateRow.removeAllViews()
            addCandidateButton("送信中…") {}
            ReportClient.submitLegacyWrongConversion(
                candidate = candidate,
                ruby = displayReading(),
                index = index,
                appVersion = packageManager.getPackageInfo(packageName, 0).versionName ?: "Unknown Version",
                learningEnabled = settings.optInt("memory_learining_styple_setting", 0) != 2,
            ) { success ->
                Handler(Looper.getMainLooper()).post {
                    candidateRow.removeAllViews()
                    addCandidateButton(if (success) "レポートを送信しました" else "送信に失敗しました") {}
                    candidateRow.postDelayed({ renderCandidates(false) }, 1600)
                }
            }
        }
        addCandidateButton("キャンセル") { renderCandidates(false) }
    }

    private fun maybeOfferReportWithoutFiltering(report: WrongConversionReport) {
        pendingReport = report
        candidateRow.removeAllViews()
        addCandidateButton("「${report.selected}」を選択") {}
        addCandidateButton("改善レポートを送信") { submitPendingReport() }
        addCandidateButton("詳細") { showReportDetails(report) }
        addCandidateButton("×") {
            pendingReport = null
            renderCandidates()
        }
    }

    private fun submitPendingReport() {
        val report = pendingReport ?: return
        candidateRow.removeAllViews()
        addCandidateButton("送信中…") {}
        ReportClient.submit(
            report = report,
            settings = settings,
            appVersion = packageManager.getPackageInfo(packageName, 0).versionName ?: "Unknown Version",
            osVersion = "Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})",
        ) { success ->
            Handler(Looper.getMainLooper()).post {
                if (success) registerReportedPair(report)
                pendingReport = null
                candidateRow.removeAllViews()
                addCandidateButton(if (success) "レポートを送信しました" else "送信に失敗しました") {}
                candidateRow.postDelayed({ renderCandidates() }, 1600)
            }
        }
    }

    private fun registerReportedPair(report: WrongConversionReport) {
        val pairKey = report.reading + "\u001f" + report.selected
        val values = mutableListOf<String>()
        val current = state.optJSONArray("reportedWrongConversionPairs") ?: JSONArray()
        for (index in 0 until current.length()) {
            val value = current.optString(index)
            if (value.isNotBlank() && value != pairKey) values.add(value)
        }
        values.add(pairKey)
        state.put("reportedWrongConversionPairs", JSONArray(values.takeLast(2048)))
        persistState()
    }

    private fun learnCandidate(reading: String, candidate: String) {
        if (settings.optInt("memory_learining_styple_setting", 0) != 0) return
        val scores = state.optJSONObject("learning") ?: JSONObject().also { state.put("learning", it) }
        val key = "$reading\t$candidate"
        scores.put(key, (scores.optInt(key, 0) + 1).coerceAtMost(1_000_000))
        persistState()
    }

    private fun persistState() {
        getSharedPreferences(MainActivity.PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit().putString(MainActivity.STATE_KEY, state.toString()).apply()
    }

    private fun commitComposition(useCandidate: Boolean = true) {
        if (composing.isEmpty() && rawRoman.isEmpty()) return
        if (settings.optBoolean("enable_zenzai", false)) zenzaiRuntime.cancel()
        val reading = displayReading()
        val text = if (useCandidate) candidates.firstOrNull() ?: buildCandidates().firstOrNull() ?: reading else reading
        learnCandidate(reading, text)
        currentInputConnection?.commitText(text, 1)
        composing = ""
        rawRoman = ""
        selectedCandidate = 0
        renderCandidates()
    }

    private fun directCommit(value: String) {
        commitComposition()
        currentInputConnection?.commitText(value, 1)
        renderCandidates()
    }

    private fun delete() {
        when {
            layout == "qwerty" && rawRoman.isNotEmpty() -> {
                rawRoman = rawRoman.dropLast(1)
                composing = romanToHiragana(rawRoman)
                if (rawRoman.isEmpty()) {
                    currentInputConnection?.finishComposingText()
                    renderCandidates()
                } else updateComposition()
            }
            composing.isNotEmpty() -> {
                composing = composing.dropLast(1)
                if (composing.isEmpty()) {
                    currentInputConnection?.finishComposingText()
                    renderCandidates()
                } else updateComposition()
            }
            else -> currentInputConnection?.deleteSurroundingText(1, 0)
        }
    }

    private fun space() {
        if (composing.isEmpty() && rawRoman.isEmpty()) {
            currentInputConnection?.commitText(" ", 1)
        } else if (settings.optBoolean("use_next_candidate_key", false) && candidates.size > 1) {
            selectedCandidate = (selectedCandidate + 1) % candidates.size
            currentInputConnection?.setComposingText(candidates[selectedCandidate], 1)
            renderCandidates(false)
        } else {
            commitComposition()
        }
    }

    private fun enter() {
        commitComposition()
        val action = currentInputEditorInfo?.imeOptions?.and(EditorInfo.IME_MASK_ACTION)
            ?: EditorInfo.IME_ACTION_NONE
        val handled = action != EditorInfo.IME_ACTION_NONE &&
            currentInputConnection?.performEditorAction(action) == true
        if (!handled) currentInputConnection?.commitText("\n", 1)
    }

    private fun toggleShift() {
        if (shift) capsLock = !capsLock
        shift = !shift || capsLock
        renderKeyboard()
    }

    private fun setMode(newMode: String) {
        commitComposition()
        mode = newMode
        activeCustomTab = null
        layout = when (newMode) {
            "japanese" -> settings.optString("keyboard_type", "flick")
            "english" -> settings.optString("keyboard_type_en", "qwerty")
            else -> "qwerty"
        }
        renderCandidates()
        renderKeyboard()
    }

    private fun nextKeyboard() {
        commitComposition()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            switchToNextInputMethod(false)
        } else {
            val manager = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
            manager.switchToNextInputMethod(window?.window?.decorView?.windowToken, false)
        }
    }

    private fun dispatchNamedAction(action: String) {
        when (action) {
            "delete" -> delete()
            "space" -> space()
            "enter" -> enter()
            "symbols" -> setMode("symbols")
            "kogana" -> transformLastCharacter()
            "shiftEnglish" -> toggleShift()
            "nextKeyboard" -> nextKeyboard()
        }
    }

    private fun dispatchAction(action: JSONObject?) {
        if (action == null) return
        val type = action.optString("type", "input")
        val value = action.optString("value", "")
        when (type) {
            "input" -> directCommit(value)
            "delete" -> repeat(value.toIntOrNull()?.coerceIn(1, 100) ?: 1) { delete() }
            "enter" -> enter()
            "space" -> space()
            "moveCursor" -> currentInputConnection?.setSelection(
                (currentInputConnection?.getTextBeforeCursor(1000, 0)?.length ?: 0) + (value.toIntOrNull() ?: 0),
                (currentInputConnection?.getTextBeforeCursor(1000, 0)?.length ?: 0) + (value.toIntOrNull() ?: 0),
            )
            "switchLayout" -> setMode(if (value == "english") "english" else "japanese")
            "paste" -> paste()
            "toggleTabBar" -> renderCandidates(true)
            "dismiss" -> requestHideSelf(0)
        }
    }

    private fun paste() {
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        val value = clipboard.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString() ?: return
        directCommit(value)
    }

    private fun transformLastCharacter() {
        if (composing.isEmpty()) return
        val last = composing.last().toString()
        val transformed = smallKana[last] ?: last
        composing = composing.dropLast(1) + transformed
        updateComposition()
    }

    private fun displayReading(): String = if (layout == "qwerty") romanToHiragana(rawRoman) else composing

    private fun feedback(view: View) {
        if (settings.optBoolean("enable_key_haptics", false)) {
            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
        }
        if (settings.optBoolean("sound_enable_setting", false)) {
            (getSystemService(AUDIO_SERVICE) as AudioManager).playSoundEffect(AudioManager.FX_KEYPRESS_STANDARD)
        }
    }

    private fun prepareZenzaiIfNeeded() {
        if (!settings.optBoolean("enable_zenzai", false)) return
        val effort = settings.optInt("zenzai_effort", 1)
        zenzaiRuntime.prepare(if (effort == 0) "xsmall" else "small")
    }

    private fun roundedDrawable(color: Int, radius: Float) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = radius
        setStroke(dp(1), Color.argb(32, 0, 0, 0))
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun renderTemplate(value: String): String {
        val now = Date()
        fun component(pattern: String) = SimpleDateFormat(pattern, Locale.JAPAN).format(now)
        return value
            .replace("yyyy", component("yyyy"))
            .replace("MM", component("MM"))
            .replace("dd", component("dd"))
            .replace("HH", component("HH"))
            .replace("mm", component("mm"))
            .replace("ss", component("ss"))
    }

    data class FlickKey(
        val label: String,
        val center: String? = null,
        val left: String? = null,
        val up: String? = null,
        val right: String? = null,
        val down: String? = null,
        val action: String? = null,
        val special: Boolean = false,
    )

    data class KeyboardPalette(
        val background: Int,
        val key: Int,
        val special: Int,
        val text: Int,
        val accent: Int,
    ) {
        companion object {
            fun default(dark: Boolean = false) = if (dark) {
                KeyboardPalette(0xff111827.toInt(), 0xff374151.toInt(), 0xff1f2937.toInt(), Color.WHITE, 0xff60a5fa.toInt())
            } else {
                KeyboardPalette(0xffd1d5db.toInt(), Color.WHITE, 0xffadb5bd.toInt(), 0xff111827.toInt(), 0xff2563eb.toInt())
            }
        }
    }

    companion object {
        private val systemDictionary = mapOf(
            "あい" to listOf("愛", "藍", "相"),
            "あう" to listOf("会う", "合う", "遭う"),
            "あさ" to listOf("朝", "麻"),
            "あした" to listOf("明日"),
            "ありがとう" to listOf("ありがとう", "有難う"),
            "いま" to listOf("今", "居間"),
            "おねがい" to listOf("お願い"),
            "きょう" to listOf("今日", "京"),
            "こんにちは" to listOf("今日は", "こんにちは"),
            "じかん" to listOf("時間"),
            "せってい" to listOf("設定"),
            "だいじょうぶ" to listOf("大丈夫"),
            "でんわ" to listOf("電話"),
            "にほん" to listOf("日本", "二本"),
            "にほんご" to listOf("日本語"),
            "へんかん" to listOf("変換"),
            "ほんじつ" to listOf("本日"),
            "よろしく" to listOf("よろしく", "宜しく"),
            "わたし" to listOf("私"),
        )
        private val emojiDictionary = mapOf(
            "えがお" to listOf("😊", "😄", "🙂"),
            "はーと" to listOf("❤️", "💕", "💙"),
            "ほし" to listOf("⭐️", "🌟", "✨"),
            "おめでとう" to listOf("🎉", "🎊"),
            "ねこ" to listOf("🐈", "🐱"),
            "いぬ" to listOf("🐕", "🐶"),
        )
        private val kaomojiDictionary = mapOf(
            "えがお" to listOf("( ´ ▽ ` )", "(^_^)", "(๑˃̵ᴗ˂̵)"),
            "かなしい" to listOf("( ; _ ; )", "(´；ω；`)"),
            "よろしく" to listOf("m(_ _)m", "よろしく(・ω・)ノ"),
        )
        private val smallKana = mapOf(
            "あ" to "ぁ", "ぁ" to "あ", "い" to "ぃ", "ぃ" to "い",
            "う" to "ぅ", "ぅ" to "ゔ", "ゔ" to "う", "え" to "ぇ", "ぇ" to "え",
            "お" to "ぉ", "ぉ" to "お", "つ" to "っ", "っ" to "づ", "づ" to "つ",
            "や" to "ゃ", "ゃ" to "や", "ゆ" to "ゅ", "ゅ" to "ゆ", "よ" to "ょ", "ょ" to "よ",
            "か" to "が", "が" to "か", "き" to "ぎ", "ぎ" to "き", "く" to "ぐ", "ぐ" to "く",
            "け" to "げ", "げ" to "け", "こ" to "ご", "ご" to "こ", "は" to "ば", "ば" to "ぱ", "ぱ" to "は",
        )
    }
}

private class AndroidZenzaiRuntime(context: Context) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "KeynakoZenzai")
    }
    private val requestSequence = AtomicLong(0)

    @Volatile
    private var loadedModelPath: String? = null

    @Volatile
    private var closed = false

    fun prepare(modelSize: String) {
        if (closed) return
        executor.execute {
            runCatching { ensureModel(modelSize) }
        }
    }

    fun rank(
        modelSize: String,
        reading: String,
        leftContext: String,
        rightContext: String,
        baseCandidates: List<String>,
        maxTokens: Int,
        callback: (List<String>) -> Unit,
    ) {
        if (closed) return
        val request = requestSequence.incrementAndGet()
        runCatching { ZenzEngine.cancelCurrent() }
        executor.execute {
            if (closed || request != requestSequence.get()) return@execute
            val result = runCatching {
                if (!ensureModel(modelSize)) return@runCatching emptyList()
                if (request != requestSequence.get()) return@runCatching emptyList()

                val generated = ZenzEngine.generateWithContextAndConditionsV32(
                    "",
                    "",
                    "",
                    "",
                    leftContext,
                    rightContext,
                    reading,
                    maxTokens,
                ).trim().takeIf { it.isPlausibleZenzaiCandidate(reading) }.orEmpty()
                if (request != requestSequence.get()) return@runCatching emptyList()

                val values = linkedSetOf<String>()
                if (generated.isNotEmpty()) values.add(generated)
                values.addAll(baseCandidates.filter { it.isNotBlank() })
                if (values.isEmpty()) return@runCatching emptyList()

                val candidates = values.toList()
                val scores = ZenzEngine.scoreCandidatesV32(
                    null,
                    null,
                    null,
                    null,
                    leftContext,
                    rightContext,
                    reading,
                    candidates.toTypedArray(),
                )
                candidates.withIndex().sortedWith(
                    compareByDescending<IndexedValue<String>> { indexed ->
                        scores.getOrNull(indexed.index)
                            ?.takeIf { it.isFinite() }
                            ?: Float.NEGATIVE_INFINITY
                    }.thenBy { it.index },
                ).map { it.value }
            }.getOrElse { emptyList() }

            if (result.isEmpty() || closed || request != requestSequence.get()) return@execute
            mainHandler.post {
                if (!closed && request == requestSequence.get()) callback(result)
            }
        }
    }

    fun cancel() {
        requestSequence.incrementAndGet()
        runCatching { ZenzEngine.cancelCurrent() }
    }

    fun close() {
        if (closed) return
        closed = true
        requestSequence.incrementAndGet()
        runCatching { ZenzEngine.cancelCurrent() }
        executor.execute {
            runCatching { ZenzEngine.closeModel() }
            loadedModelPath = null
        }
        executor.shutdown()
    }

    private fun ensureModel(modelSize: String): Boolean {
        if (closed) return false
        val model = ZenzaiModelManager(appContext).prepare(modelSize) ?: return false
        if (loadedModelPath != model.absolutePath) {
            if (loadedModelPath != null) ZenzEngine.closeModel()
            if (!ZenzEngine.initModel(model.absolutePath)) {
                loadedModelPath = null
                return false
            }
            loadedModelPath = model.absolutePath
        }
        val threads = Runtime.getRuntime().availableProcessors().coerceIn(1, 4)
        ZenzEngine.setRuntimeConfig(512, threads)
        return true
    }
}

private fun String.isPlausibleZenzaiCandidate(reading: String): Boolean {
    if (isEmpty()) return false
    val maximumLength = maxOf(48, reading.length * 3 + 24)
    if (length > maximumLength) return false
    return none { char ->
        char == '\uFFFD' ||
            char in '\uE000'..'\uF8FF' ||
            (char.isISOControl() && char != '\n' && char != '\t')
    }
}

private class ZenzaiModelManager(private val context: Context) {
    fun prepare(size: String): File? {
        val expectedSize = if (size == "xsmall") 20_970_304L else 73_871_936L
        val folder = "zenz-v3.2-$size-gguf"
        val destination = File(context.filesDir, "zenzai/$folder/ggml-model-Q5_K_M.gguf")
        if (destination.length() == expectedSize) return destination
        return try {
            destination.parentFile?.mkdirs()
            val asset = "$folder/ggml-model-Q5_K_M.gguf"
            context.assets.open(asset).use { input ->
                FileOutputStream(destination).use { output -> input.copyTo(output, 1024 * 1024) }
            }
            if (destination.length() == expectedSize) destination else null
        } catch (_: Exception) {
            null
        }
    }
}

private val halfWidthKanaMap: Map<Char, String> = run {
    val full = "。「」、・ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヰヱヲン゙゚"
    val half = "｡｢｣､･ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜｲｴｦﾝﾞﾟ"
    full.zip(half).associate { (source, target) -> source to target.toString() } + mapOf(
        'ヮ' to "ﾜ",
        'ヵ' to "ｶ",
        'ヶ' to "ｹ",
    )
}

private fun katakanaToHalfWidth(value: String): String = buildString {
    val decomposed = Normalizer.normalize(value, Normalizer.Form.NFD)
    for (char in decomposed) append(halfWidthKanaMap[char] ?: char.toString())
}

private fun asciiToFullWidth(value: String): String = buildString {
    for (char in value) {
        append(
            when (char) {
                ' ' -> '　'
                in '!'..'~' -> (char.code + 0xfee0).toChar()
                else -> char
            },
        )
    }
}

private fun unicodeCandidate(value: String): String? {
    val hex = Regex("(?i)^u\\+?([0-9a-f]{1,6})$").matchEntire(value)?.groupValues?.get(1) ?: return null
    val codePoint = hex.toIntOrNull(16) ?: return null
    if (!Character.isValidCodePoint(codePoint) || codePoint in 0xd800..0xdfff) return null
    return String(Character.toChars(codePoint))
}

private fun toMathematicalBold(value: String): String = buildString {
    for (char in value) {
        val codePoint = when (char) {
            in 'A'..'Z' -> 0x1d400 + (char - 'A')
            in 'a'..'z' -> 0x1d41a + (char - 'a')
            in '0'..'9' -> 0x1d7ce + (char - '0')
            else -> char.code
        }
        append(String(Character.toChars(codePoint)))
    }
}

private fun romanToHiragana(input: String): String {
    val result = StringBuilder()
    var index = 0
    val lower = input.lowercase()
    while (index < lower.length) {
        val current = lower[index]
        if (index + 1 < lower.length && current == lower[index + 1] && current in "bcdfghjklmpqrstvwxyz" && current != 'n') {
            result.append('っ')
            index += 1
            continue
        }
        if (current == 'n' && index + 1 < lower.length && lower[index + 1] !in "aiueoyn") {
            result.append('ん')
            index += 1
            continue
        }
        var found: String? = null
        var consumed = 0
        for (length in listOf(4, 3, 2, 1)) {
            if (index + length > lower.length) continue
            val replacement = romanMap[lower.substring(index, index + length)] ?: continue
            found = replacement
            consumed = length
            break
        }
        if (found == null) {
            result.append(lower[index])
            index += 1
        } else {
            result.append(found)
            index += consumed
        }
    }
    if (result.endsWith("n")) result.replace(result.length - 1, result.length, "ん")
    return result.toString()
}

private fun hiraganaToKatakana(value: String): String = buildString {
    for (char in value) {
        append(if (char.code in 0x3041..0x3096) (char.code + 0x60).toChar() else char)
    }
}

private val romanMap = mapOf(
    "kya" to "きゃ", "kyu" to "きゅ", "kyo" to "きょ", "gya" to "ぎゃ", "gyu" to "ぎゅ", "gyo" to "ぎょ",
    "sha" to "しゃ", "shu" to "しゅ", "sho" to "しょ", "sya" to "しゃ", "syu" to "しゅ", "syo" to "しょ",
    "jya" to "じゃ", "jyu" to "じゅ", "jyo" to "じょ", "cha" to "ちゃ", "chu" to "ちゅ", "cho" to "ちょ",
    "nya" to "にゃ", "nyu" to "にゅ", "nyo" to "にょ", "hya" to "ひゃ", "hyu" to "ひゅ", "hyo" to "ひょ",
    "mya" to "みゃ", "myu" to "みゅ", "myo" to "みょ", "rya" to "りゃ", "ryu" to "りゅ", "ryo" to "りょ",
    "fa" to "ふぁ", "fi" to "ふぃ", "fe" to "ふぇ", "fo" to "ふぉ", "she" to "しぇ", "che" to "ちぇ", "je" to "じぇ",
    "ka" to "か", "ki" to "き", "ku" to "く", "ke" to "け", "ko" to "こ", "ga" to "が", "gi" to "ぎ", "gu" to "ぐ", "ge" to "げ", "go" to "ご",
    "sa" to "さ", "si" to "し", "shi" to "し", "su" to "す", "se" to "せ", "so" to "そ", "za" to "ざ", "zi" to "じ", "ji" to "じ", "zu" to "ず", "ze" to "ぜ", "zo" to "ぞ",
    "ta" to "た", "ti" to "ち", "chi" to "ち", "tu" to "つ", "tsu" to "つ", "te" to "て", "to" to "と", "da" to "だ", "di" to "ぢ", "du" to "づ", "de" to "で", "do" to "ど",
    "na" to "な", "ni" to "に", "nu" to "ぬ", "ne" to "ね", "no" to "の", "ha" to "は", "hi" to "ひ", "hu" to "ふ", "fu" to "ふ", "he" to "へ", "ho" to "ほ",
    "ba" to "ば", "bi" to "び", "bu" to "ぶ", "be" to "べ", "bo" to "ぼ", "pa" to "ぱ", "pi" to "ぴ", "pu" to "ぷ", "pe" to "ぺ", "po" to "ぽ",
    "ma" to "ま", "mi" to "み", "mu" to "む", "me" to "め", "mo" to "も", "ya" to "や", "yu" to "ゆ", "yo" to "よ",
    "ra" to "ら", "ri" to "り", "ru" to "る", "re" to "れ", "ro" to "ろ", "wa" to "わ", "wo" to "を", "nn" to "ん",
    "la" to "ぁ", "li" to "ぃ", "lu" to "ぅ", "le" to "ぇ", "lo" to "ぉ", "ltu" to "っ", "xtu" to "っ",
    "a" to "あ", "i" to "い", "u" to "う", "e" to "え", "o" to "お", "-" to "ー", "," to "、", "." to "。",
)
