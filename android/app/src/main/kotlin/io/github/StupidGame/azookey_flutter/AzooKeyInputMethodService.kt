package io.github.StupidGame.azookey_flutter

import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.inputmethodservice.InputMethodService
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.net.Uri
import android.util.Log
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.PopupWindow
import android.widget.ScrollView
import android.widget.TextView
import androidx.exifinterface.media.ExifInterface
import io.github.StupidGame.azookey_flutter.conversion.AndroidZenzaiRuntime
import io.github.StupidGame.azookey_flutter.conversion.AzooKeyDictionary
import io.github.StupidGame.azookey_flutter.conversion.AzooKeyHotfixDictionaryEntry
import io.github.StupidGame.azookey_flutter.conversion.DictionaryAssetSource
import io.github.StupidGame.azookey_flutter.conversion.DictionaryCandidates
import io.github.StupidGame.azookey_flutter.conversion.JapaneseInputContext
import io.github.StupidGame.azookey_flutter.conversion.asciiToFullWidth
import io.github.StupidGame.azookey_flutter.conversion.compositionCommitText
import io.github.StupidGame.azookey_flutter.conversion.defaultScanTargets
import io.github.StupidGame.azookey_flutter.conversion.englishPredictionCandidates
import io.github.StupidGame.azookey_flutter.conversion.hiraganaToKatakana
import io.github.StupidGame.azookey_flutter.conversion.katakanaToHalfWidth
import io.github.StupidGame.azookey_flutter.conversion.katakanaToHiragana
import io.github.StupidGame.azookey_flutter.conversion.pinJapaneseKanaCandidates
import io.github.StupidGame.azookey_flutter.conversion.prefixPredictionValues
import io.github.StupidGame.azookey_flutter.conversion.prioritizePrefixPredictions
import io.github.StupidGame.azookey_flutter.conversion.romanToHiragana
import io.github.StupidGame.azookey_flutter.conversion.shouldDirectCommitJapaneseInput
import io.github.StupidGame.azookey_flutter.conversion.toMathematicalBold
import io.github.StupidGame.azookey_flutter.conversion.unicodeCandidate
import io.github.StupidGame.azookey_flutter.input.FlickLongPressSelection
import io.github.StupidGame.azookey_flutter.input.FiredLongPressTransition
import io.github.StupidGame.azookey_flutter.input.CustardDeleteContinuationAction
import io.github.StupidGame.azookey_flutter.input.TextSelectionSession
import io.github.StupidGame.azookey_flutter.input.backwardSmartDeleteContinuationStartIndex
import io.github.StupidGame.azookey_flutter.input.backgroundImageOrientationTransform
import io.github.StupidGame.azookey_flutter.input.combinedBackwardSmartDeleteCount
import io.github.StupidGame.azookey_flutter.input.custardFlickDirection
import io.github.StupidGame.azookey_flutter.input.defaultSymbolKeyboardRows
import io.github.StupidGame.azookey_flutter.input.firedLongPressTransition
import io.github.StupidGame.azookey_flutter.input.kanaCharacterFormReplacement
import io.github.StupidGame.azookey_flutter.input.lastCharactersReplacementIn
import io.github.StupidGame.azookey_flutter.input.longPressDelayMillis
import io.github.StupidGame.azookey_flutter.input.smartDeleteCount
import io.github.StupidGame.azookey_flutter.input.surroundingDeleteFor
import io.github.StupidGame.azookey_flutter.view.CustardGridLayout
import io.github.StupidGame.azookey_flutter.view.DirectionalKeyView
import io.github.StupidGame.azookey_flutter.view.custardSystemImageLabel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.random.Random

class AzooKeyInputMethodService : InputMethodService() {
    private lateinit var inputViewFrame: FrameLayout
    private lateinit var backgroundImageView: KeyboardBackgroundImageView
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
    private var oneHandedMode = "full"
    private var candidates = mutableListOf<String>()
    private var pendingReport: WrongConversionReport? = null
    private var hotfixDictionaryEntries = emptyList<AzooKeyHotfixDictionaryEntry>()
    private var hotfixDictionaryVersion = "none"
    private var backgroundImageSignature: String? = null
    private var hasLoadedState = false
    private var palette = KeyboardPalette.default()
    private var flickGuide: FlickGuide? = null
    private var cursorBarVisible = false
    private var cursorBarView: CursorBarView? = null
    private val azooKeyDictionary by lazy {
        AzooKeyDictionary(
            DictionaryAssetSource { path ->
                assets.open("Dictionary/$path").use { it.readBytes() }
            },
        )
    }
    private val zenzaiRuntime by lazy { AndroidZenzaiRuntime(this) }

    override fun onCreate() {
        super.onCreate()
        activeInstance = this
    }

    override fun onDestroy() {
        dismissFlickGuide()
        if (activeInstance === this) activeInstance = null
        if (this::root.isInitialized) zenzaiRuntime.close()
        super.onDestroy()
    }

    /** Reload Flutter state while the IME is already open. */
    fun refreshFromApp() {
        if (!::root.isInitialized) return
        reloadState()
        applyKeyboardBackground()
        renderCandidates()
        renderKeyboard()
        prepareZenzaiIfNeeded()
    }

    override fun onCreateInputView(): View {
        reloadState()
        inputViewFrame = FrameLayout(this).apply {
            setBackgroundColor(palette.background)
        }
        backgroundImageView = KeyboardBackgroundImageView(this).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            imageAlpha = 217
            visibility = View.GONE
        }
        inputViewFrame.addView(
            backgroundImageView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        inputViewFrame.addView(
            root,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        applyKeyboardBackground()
        applyKeyboardWidth()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            inputViewFrame.setOnApplyWindowInsetsListener { view, insets ->
                val bottom = insets.getInsets(WindowInsets.Type.navigationBars()).bottom
                if (view.paddingBottom != bottom) {
                    view.setPadding(0, 0, 0, bottom)
                    view.requestLayout()
                }
                insets
            }
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
        return inputViewFrame
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        if (::root.isInitialized && settings.optBoolean("enable_zenzai", true)) {
            zenzaiRuntime.cancel()
        }
        reloadState()
        composing = ""
        rawRoman = ""
        selectedCandidate = 0
        cursorBarVisible = false
        cursorBarView = null
        activeCustomTab = getSharedPreferences(MainActivity.PREFERENCES_NAME, Context.MODE_PRIVATE)
            .getString(ACTIVE_CUSTOM_TAB_KEY, null)
            ?.trim()
            ?.takeIf(String::isNotEmpty)
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
            applyKeyboardBackground()
            applyKeyboardWidth()
            renderCandidates()
            renderKeyboard()
            prepareZenzaiIfNeeded()
        }
    }

    private fun reloadState() {
        val preferences = getSharedPreferences(
            MainActivity.PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        )
        val value = preferences.getString(MainActivity.STATE_KEY, null)
        oneHandedMode = preferences.getString(ONE_HANDED_MODE_KEY, "full")
            ?.takeIf { it == "left" || it == "right" }
            ?: "full"
        val restoredState = try {
            value?.takeIf(String::isNotBlank)?.let(::JSONObject)
        } catch (_: Exception) {
            null
        }
        if (restoredState != null) {
            state = restoredState
            hasLoadedState = true
        } else if (hasLoadedState) {
            // Keep the last valid palette if preferences are briefly unavailable
            // while the settings app replaces its state.
            return
        } else {
            state = JSONObject()
        }
        settings = state.optJSONObject("settings") ?: JSONObject()
        reloadAzooKeyHotfixDictionary()
        if (settings.has("memory_reset_setting") && settings.opt("memory_reset_setting") != false) {
            state.put("learning", JSONObject())
            settings.put("memory_reset_setting", false)
            state.put("settings", settings)
            persistState()
        }
        palette = loadPalette()
    }

    private fun reloadAzooKeyHotfixDictionary() {
        val tag = state.optString(KEYNAKO_HOTFIX_LATEST_SHA_KEY).ifBlank {
            state.optString(LEGACY_AZOOKEY_HOTFIX_LATEST_TAG_KEY, "none")
        }
        val dictionary = state.optJSONObject(KEYNAKO_HOTFIX_STORAGE_KEY)
            ?: state.optJSONObject(LEGACY_AZOOKEY_HOTFIX_STORAGE_KEY)
        val metadata = dictionary?.optJSONObject("metadata")
        val values = dictionary?.optJSONArray("data")
        if (metadata?.optString("status") != "active" || values == null) {
            hotfixDictionaryEntries = emptyList()
            hotfixDictionaryVersion = "$tag|disabled"
            return
        }
        hotfixDictionaryEntries = buildList {
            for (index in 0 until values.length()) {
                val value = values.optJSONObject(index) ?: continue
                val word = value.optString("word")
                val ruby = value.optString("ruby")
                val wordWeight = value.optDouble("word_weight", Double.NaN)
                if (word.isEmpty() || ruby.isEmpty() || !wordWeight.isFinite()) continue
                add(
                    AzooKeyHotfixDictionaryEntry(
                        word = word,
                        ruby = ruby,
                        wordWeight = wordWeight,
                        lcid = value.optInt("lcid"),
                        rcid = value.optInt("rcid"),
                        mid = value.optInt("mid"),
                    ),
                )
            }
        }
        hotfixDictionaryVersion =
            "$tag|${metadata.optString("last_update", "unknown")}|${hotfixDictionaryEntries.size}"
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
                val backgroundImage = theme.optString("backgroundImage")
                    .takeIf(String::isNotBlank)
                val keyOpacity = if (backgroundImage == null) {
                    1.0
                } else {
                    theme.optDouble("keyOpacity", 0.72).coerceIn(0.15, 1.0)
                }
                return KeyboardPalette(
                    background = theme.optLong("backgroundColor", 0xffd1d5dbL).toInt(),
                    key = withOpacity(
                        theme.optLong("keyColor", 0xffffffffL).toInt(),
                        keyOpacity,
                    ),
                    special = withOpacity(
                        theme.optLong("specialKeyColor", 0xffadb5bdL).toInt(),
                        keyOpacity,
                    ),
                    text = theme.optLong("textColor", 0xff111827L).toInt(),
                    accent = withOpacity(
                        theme.optLong("accentColor", 0xff2563ebL).toInt(),
                        keyOpacity,
                    ),
                    backgroundImage = backgroundImage,
                    backgroundImageRevision = theme
                        .optLong("backgroundImageRevision", 0L)
                        .takeIf { it > 0L },
                )
            }
        }
        return KeyboardPalette.default(night)
    }

    private fun applyKeyboardBackground() {
        inputViewFrame.setBackgroundColor(palette.background)
        val configuredPath = palette.backgroundImage
        val file = configuredPath?.let(::File)?.takeIf { it.isFile }
        val signature = file?.let {
            val revision = palette.backgroundImageRevision ?: it.lastModified()
            "${it.absolutePath}:$revision"
        }
        if (configuredPath == null) {
            backgroundImageView.setImageDrawable(null)
            backgroundImageSignature = null
        } else if (signature != null && shouldReloadKeyboardBackground(
                signature = signature,
                loadedSignature = backgroundImageSignature,
                hasDrawable = backgroundImageView.drawable != null,
            )
        ) {
            val bitmap = file.let(::decodeKeyboardBackground)
            if (bitmap != null) {
                backgroundImageView.setImageBitmap(bitmap)
                backgroundImageSignature = signature
            } else {
                Log.w(
                    "KeynakoIME",
                    "Keeping the previous keyboard background after a decode failure",
                )
            }
        }
        // A state/file replacement is atomic, but the filesystem can still be
        // briefly unavailable. Keep the already decoded image instead of
        // flashing the palette fallback until the next refresh.
        val hasImage = configuredPath != null && backgroundImageView.drawable != null
        backgroundImageView.visibility = if (hasImage) View.VISIBLE else View.GONE
        root.setBackgroundColor(if (hasImage) Color.TRANSPARENT else palette.background)
    }

    private fun decodeKeyboardBackground(file: File): Bitmap? {
        val source = BitmapFactory.decodeFile(file.absolutePath) ?: return null
        val exifOrientation = runCatching {
            ExifInterface(file.absolutePath).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        val transform = backgroundImageOrientationTransform(exifOrientation)
        if (transform.rotationDegrees == 0 && !transform.flipHorizontally) return source
        val matrix = Matrix().apply {
            if (transform.flipHorizontally) postScale(-1f, 1f)
            if (transform.rotationDegrees != 0) postRotate(transform.rotationDegrees.toFloat())
        }
        return try {
            Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true).also {
                if (it !== source) source.recycle()
            }
        } catch (_: RuntimeException) {
            source
        }
    }

    private fun renderKeyboard() {
        dismissFlickGuide()
        keyboardContainer.removeAllViews()
        val heightScale = settings.optDouble("keyboard_height_scale", 1.0).coerceIn(0.7, 1.4)
        try {
            when {
                activeCustomTab != null -> renderCustomTab(activeCustomTab!!, heightScale)
                mode == "symbols" -> renderSymbols(heightScale)
                layout == "qwerty" -> renderQwerty(heightScale)
                else -> renderFlick(heightScale)
            }
        } catch (_: RuntimeException) {
            // A malformed imported custom tab must not take down the IME or
            // silently turn into the built-in Japanese layout.
            keyboardContainer.removeAllViews()
            if (activeCustomTab != null) renderCustomTabFooter(heightScale)
            else if (mode == "symbols") renderSymbols(heightScale)
            else if (layout == "qwerty") renderQwerty(heightScale)
            else renderFlick(heightScale)
        }
        if (activeCustomTab == null) renderStandaloneCustomKeys(heightScale)
    }

    private fun renderFlick(scale: Double) {
        val keys = if (mode == "english") listOf(
            listOf(
                FlickKey("☆123", action = "symbols", special = true, customTarget = "symbols_tab"),
                FlickKey("@#/&_", "@", "#", "/", "&", "_"),
                FlickKey("ABC", "a", "b", "c", "2", null),
                FlickKey("DEF", "d", "e", "f", "3", null),
                FlickKey("⌫", left = "×", action = "delete", special = true),
            ),
            listOf(
                FlickKey("ABC", action = "english", special = true, customTarget = "abc_tab"),
                FlickKey("GHI", "g", "h", "i", "4", null),
                FlickKey("JKL", "j", "k", "l", "5", null),
                FlickKey("MNO", "m", "n", "o", "6", null),
                FlickKey("空白", "空白", "←", "　", "→", "\t", action = "space", special = true),
            ),
            listOf(
                FlickKey("あいう", action = "japanese", special = true, customTarget = "hira_tab"),
                FlickKey("PQRS", "p", "q", "r", "s", "7"),
                FlickKey("TUV", "t", "u", "v", "8", null),
                FlickKey("WXYZ", "w", "x", "y", "z", "9"),
                FlickKey("改行", action = "enter", special = true),
            ),
            listOf(
                FlickKey(""),
                FlickKey(if (shift || capsLock) "A/a" else "a/A", action = "shiftEnglish", special = true),
                FlickKey("'\"()", "'", "\"", "(", ")", null),
                FlickKey(".,?!", ".", ",", "?", "!", "'", customTarget = "kana_symbols"),
                FlickKey(""),
            ),
        ) else listOf(
            listOf(
                FlickKey("☆123", action = "symbols", special = true, customTarget = "symbols_tab"),
                FlickKey("あ", "あ", "い", "う", "え", "お"),
                FlickKey("か", "か", "き", "く", "け", "こ"),
                FlickKey("さ", "さ", "し", "す", "せ", "そ"),
                FlickKey("⌫", left = "×", action = "delete", special = true),
            ),
            listOf(
                FlickKey("ABC", action = "english", special = true, customTarget = "abc_tab"),
                FlickKey("た", "た", "ち", "つ", "て", "と"),
                FlickKey("な", "な", "に", "ぬ", "ね", "の"),
                FlickKey("は", "は", "ひ", "ふ", "へ", "ほ"),
                FlickKey("空白", "空白", "←", "　", "→", "\t", action = "space", special = true),
            ),
            listOf(
                FlickKey("あいう", action = "japanese", special = true, customTarget = "hira_tab"),
                FlickKey("ま", "ま", "み", "む", "め", "も"),
                FlickKey("や", "や", "「", "ゆ", "」", "よ"),
                FlickKey("ら", "ら", "り", "る", "れ", "ろ"),
                FlickKey("改行", action = "enter", special = true),
            ),
            listOf(
                FlickKey(""),
                FlickKey("小ﾞﾟ", action = "kogana", special = true, customTarget = "kogana"),
                FlickKey("わ", "わ", "を", "ん", "ー", "〜"),
                FlickKey("､｡?!", "、", "。", "？", "！", null, customTarget = "kana_symbols"),
                FlickKey(""),
            ),
        )
        val grid = CustardGridLayout(this, columns = 5, rows = 4).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                (dp(47) * scale * 4).toInt(),
            )
        }
        for ((rowIndex, row) in keys.withIndex()) {
            for ((columnIndex, key) in row.withIndex()) {
                if (rowIndex == 3 && columnIndex == 4) continue
                val custom = key.customTarget?.let(::customKeyForTarget)
                val keyView = when {
                    custom != null -> createCustomKey(custom, scale)
                    key.label.isEmpty() && key.action == null -> View(this)
                    else -> createFlickKey(key, scale)
                }
                grid.addPositionedView(
                    keyView,
                    x = columnIndex.toDouble(),
                    y = rowIndex.toDouble(),
                    width = 1.0,
                    height = if (rowIndex == 2 && columnIndex == 4) 2.0 else 1.0,
                )
            }
        }
        keyboardContainer.addView(grid)
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
        bottom.addView(View(this), weightParams(1.2f))
        bottom.addView(createKey("space", false, scale) { space() }, weightParams(4f))
        bottom.addView(createKey("return", true, scale) { enter() }, weightParams(2f))
        keyboardContainer.addView(bottom)
    }

    private fun renderSymbols(scale: Double) {
        for (values in defaultSymbolKeyboardRows) {
            val row = newRow(scale)
            for (value in values) {
                row.addView(
                    createFlickKey(
                        FlickKey(
                            label = value.halfWidth,
                            center = value.halfWidth,
                            up = value.fullWidth,
                        ),
                        scale,
                    ),
                    weightParams(),
                )
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
        val normalizedId = id.trim()
        if (renderCustard(normalizedId, scale)) return
        val target = customTabDefinition(normalizedId)
        if (target == null) {
            Log.w(IME_LOG_TAG, "Custom tab '$normalizedId' was selected but is not in the saved state")
            renderCustomTabFooter(scale)
            return
        }
        val columns = target.optInt("columns", 4).coerceIn(1, 8)
        val keys = target.optJSONArray("keys") ?: JSONArray()
        var row = newRow(scale)
        var count = 0
        for (index in 0 until keys.length()) {
            val key = keys.optJSONObject(index) ?: continue
            val label = key.optString("label", "")
            runCatching { createCustomKey(key, scale) }
                .onSuccess { row.addView(it, weightParams()) }
                .onFailure { Log.w(IME_LOG_TAG, "Skipping malformed custom key", it) }
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
        renderCustomTabFooter(scale)
    }

    private fun renderCustomTabFooter(scale: Double) {
        val bottom = newRow(scale)
        bottom.addView(createKey("タブ", true, scale) { renderCandidates(true) }, weightParams())
        bottom.addView(createKey("あいう", true, scale) { setMode("japanese") }, weightParams())
        bottom.addView(createKey("⌫", true, scale) { delete() }, weightParams())
        bottom.addView(createKey("space", false, scale) { space() }, weightParams(2f))
        bottom.addView(createKey("return", true, scale) { enter() }, weightParams())
        keyboardContainer.addView(bottom)
    }

    private fun customTabDefinition(id: String): JSONObject? {
        val tabs = state.optJSONArray("customTabs") ?: return null
        for (index in 0 until tabs.length()) {
            val tab = tabs.optJSONObject(index) ?: continue
            if (tab.optString("id").trim() == id) return tab
        }
        return null
    }

    private fun renderCustard(id: String, scale: Double): Boolean {
        val custards = state.optJSONArray("custards") ?: return false
        var custard: JSONObject? = null
        for (index in 0 until custards.length()) {
            val candidate = custards.optJSONObject(index) ?: continue
            if (candidate.optString("identifier") == id) {
                custard = candidate
                break
            }
        }
        val definition = custard ?: return false
        val interfaceData = definition.optJSONObject("interface") ?: return false
        val layoutData = interfaceData.optJSONObject("key_layout") ?: return false
        val keys = interfaceData.optJSONArray("keys") ?: JSONArray()
        val keyStyle = interfaceData.optString("key_style", "tenkey_style")
        return when (layoutData.optString("type", "grid_fit")) {
            "grid_scroll" -> {
                renderCustardScroll(layoutData, keys, keyStyle, scale)
                true
            }
            else -> {
                renderCustardGrid(layoutData, keys, keyStyle, scale)
                true
            }
        }
    }

    private fun renderCustardGrid(
        layoutData: JSONObject,
        keys: JSONArray,
        keyStyle: String,
        scale: Double,
    ) {
        // Custard's row_count is the horizontal cell count and column_count
        // is the vertical cell count. Coordinates outside that declared grid
        // are not part of the layout; ignore them instead of moving them to
        // the last row/column. This is important for layouts that include
        // optional keys for another tab or version.
        val columns = layoutData.optDouble("row_count", 4.0).toInt().coerceIn(1, 40)
        val rows = layoutData.optDouble("column_count", 5.0).toInt().coerceIn(1, 40)
        val grid = CustardGridLayout(this, columns, rows)
        val cellHeight = (dp(47) * scale).toInt().coerceAtLeast(dp(32))
        for (index in 0 until keys.length()) {
            val element = keys.optJSONObject(index) ?: continue
            if (element.optString("specifier_type") != "grid_fit") continue
            val specifier = element.optJSONObject("specifier") ?: continue
            val x = specifier.optDouble("x", 0.0)
            val y = specifier.optDouble("y", 0.0)
            if (x < 0.0 || y < 0.0 || x >= columns || y >= rows) continue
            val width = specifier.optDouble("width", 1.0).coerceIn(0.01, columns - x)
            val height = specifier.optDouble("height", 1.0).coerceIn(0.01, rows - y)
            val view = createCustardKey(element, keyStyle, scale)
            grid.addPositionedView(view, x, y, width, height)
        }
        keyboardContainer.addView(
            grid,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                cellHeight * rows,
            ),
        )
    }

    private fun renderCustardScroll(
        layoutData: JSONObject,
        keys: JSONArray,
        keyStyle: String,
        scale: Double,
    ) {
        val elements = (0 until keys.length()).mapNotNull(keys::optJSONObject)
            .filter { it.optString("specifier_type") == "grid_scroll" }
            .sortedBy { it.optJSONObject("specifier")?.optInt("index") ?: Int.MAX_VALUE }
        val crossCount = layoutData.optDouble("row_count", 4.0).toInt().coerceIn(1, 20)
        val visibleCount = layoutData.optDouble("column_count", 4.0).coerceIn(1.0, 20.0)
        val cellHeight = (dp(47) * scale).toInt().coerceAtLeast(dp(32))
        if (layoutData.optString("direction", "vertical") == "horizontal") {
            val cellWidth = (resources.displayMetrics.widthPixels / visibleCount).toInt()
            val content = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            for (start in elements.indices step crossCount) {
                val column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
                for (index in start until minOf(start + crossCount, elements.size)) {
                    column.addView(
                        createCustardKey(elements[index], keyStyle, scale, variationsEnabled = false),
                        LinearLayout.LayoutParams(cellWidth, cellHeight).apply {
                            setMargins(dp(2), dp(2), dp(2), dp(2))
                        },
                    )
                }
                content.addView(column)
            }
            val scroll = HorizontalScrollView(this).apply {
                isHorizontalScrollBarEnabled = false
                addView(content)
            }
            keyboardContainer.addView(
                scroll,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    cellHeight * crossCount,
                ),
            )
        } else {
            val content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
            for (start in elements.indices step crossCount) {
                val row = newRow(scale)
                for (index in start until minOf(start + crossCount, elements.size)) {
                    row.addView(
                        createCustardKey(elements[index], keyStyle, scale, variationsEnabled = false),
                        weightParams(),
                    )
                }
                while (row.childCount < crossCount) row.addView(View(this), weightParams())
                content.addView(row)
            }
            val scroll = ScrollView(this).apply {
                isVerticalScrollBarEnabled = false
                addView(content)
            }
            keyboardContainer.addView(
                scroll,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    (cellHeight * visibleCount).toInt(),
                ),
            )
        }
    }

    private fun createCustardKey(
        element: JSONObject,
        keyStyle: String,
        scale: Double,
        variationsEnabled: Boolean = true,
    ): View {
        val key = element.optJSONObject("key") ?: JSONObject()
        if (element.optString("key_type") == "system") {
            return createCustardSystemKey(key.optString("type"), scale)
        }
        val design = key.optJSONObject("design") ?: JSONObject()
        val color = design.optString("color", "normal")
        val label = design.optJSONObject("label")
        val fullCenterLabel = custardLabel(label)
        val flickVariations = if (variationsEnabled) custardVariations(key, "flick_variation") else emptyList()
        fun variationLabel(direction: String): String? {
            val variationKey = flickVariations
                .firstOrNull { it.optString("direction") == direction }
                ?.optJSONObject("key")
                ?: return null
            return variationKey.optJSONObject("design")
                ?.optJSONObject("label")
                ?.let(::custardLabel)
                ?.takeIf(String::isNotEmpty)
                ?: variationKey.optJSONArray("press_actions")
                    ?.optJSONObject(0)
                    ?.let(::actionDisplayLabel)
        }
        val leftLabel = variationLabel("left") ?: custardDirectionLabel(label, "left")
        val upLabel = variationLabel("top") ?: custardDirectionLabel(label, "top")
        val rightLabel = variationLabel("right") ?: custardDirectionLabel(label, "right")
        val downLabel = variationLabel("bottom") ?: custardDirectionLabel(label, "bottom")
        val special = color == "special" || color == "unimportant"
        val hasDirectionLabels = listOf(leftLabel, upLabel, rightLabel, downLabel).any { !it.isNullOrEmpty() }
        val centerLabel = if (hasDirectionLabels) custardPrimaryLabel(label) else fullCenterLabel
        val view = if (hasDirectionLabels) {
            createDirectionalKey(
                centerLabel,
                leftLabel,
                upLabel,
                rightLabel,
                downLabel,
                special,
            )
        } else {
            createKey(centerLabel, special, scale, null)
        }
        if (color == "selected") view.background = roundedDrawable(palette.accent, dp(6).toFloat())
        val handler = Handler(Looper.getMainLooper())
        var startX = 0f
        var startY = 0f
        var didLongPress = false
        var repeating = false
        var longPressFlicked = false
        var variationDidLongPress = false
        var continueDeleteVariationOnRelease = false
        var centerLongPressCheckpoint: CompositionSnapshot? = null
        val longPressSelection = FlickLongPressSelection(key)
        val longPressData = key.optJSONObject("longpress_actions") ?: JSONObject()
        val startActions = longPressData.optJSONArray("start") ?: JSONArray()
        var activeRepeatActions = longPressData.optJSONArray("repeat") ?: JSONArray()
        val pcVariations = if (variationsEnabled && keyStyle == "pc_style") {
            custardVariations(key, "longpress_variation")
        } else {
            emptyList()
        }
        val handlesLongPress = startActions.length() > 0 || activeRepeatActions.length() > 0 ||
            pcVariations.isNotEmpty() || flickVariations.any { variation ->
                val variationLongPress = variation.optJSONObject("key")?.optJSONObject("longpress_actions")
                (variationLongPress?.optJSONArray("start")?.length() ?: 0) > 0 ||
                    (variationLongPress?.optJSONArray("repeat")?.length() ?: 0) > 0
            }
        val repeatAction = object : Runnable {
            override fun run() {
                if (!repeating) return
                dispatchActions(activeRepeatActions)
                handler.postDelayed(this, 70)
            }
        }
        val longPress = Runnable {
            val selectedKey = longPressSelection.target ?: return@Runnable
            val selectedLongPress = selectedKey.optJSONObject("longpress_actions") ?: JSONObject()
            val selectedStartActions = selectedLongPress.optJSONArray("start") ?: JSONArray()
            activeRepeatActions = selectedLongPress.optJSONArray("repeat") ?: JSONArray()
            if (selectedStartActions.length() == 0 && activeRepeatActions.length() == 0 && pcVariations.isEmpty()) {
                return@Runnable
            }
            centerLongPressCheckpoint = if (
                longPressSelection.direction == null &&
                canRollbackCustardInputActions(selectedStartActions, activeRepeatActions)
            ) {
                compositionSnapshot()
            } else {
                null
            }
            didLongPress = true
            variationDidLongPress = longPressSelection.direction != null
            dismissFlickGuide()
            dispatchActions(selectedStartActions)
            if (activeRepeatActions.length() > 0) {
                repeating = true
                handler.postDelayed(repeatAction, 70)
            }
            feedback(view)
        }
        view.setOnTouchListener { target, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.x
                    startY = event.y
                    didLongPress = false
                    repeating = false
                    longPressFlicked = false
                    variationDidLongPress = false
                    continueDeleteVariationOnRelease = false
                    centerLongPressCheckpoint = null
                    activeRepeatActions = longPressData.optJSONArray("repeat") ?: JSONArray()
                    target.isPressed = true
                    longPressSelection.reset()
                    val delay = longPressDelay(longPressData.optString("duration"))
                    if (handlesLongPress) handler.postDelayed(longPress, delay)
                    showFlickGuide(target, centerLabel, leftLabel, upLabel, rightLabel, downLabel)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    handler.removeCallbacks(longPress)
                    repeating = false
                    handler.removeCallbacks(repeatAction)
                    centerLongPressCheckpoint = null
                    target.isPressed = false
                    dismissFlickGuide()
                    val dx = event.x - startX
                    val dy = event.y - startY
                    if (longPressFlicked) {
                        if (!variationDidLongPress) {
                            val threshold = dp(20).toFloat() *
                                settings.optDouble("flick_sensitivity_setting", 1.0).toFloat()
                            val direction = if (!variationsEnabled || abs(dx) < threshold && abs(dy) < threshold) null
                            else if (abs(dx) > abs(dy)) if (dx < 0) "left" else "right"
                            else if (dy < 0) "top" else "bottom"
                            val variation = if (continueDeleteVariationOnRelease) {
                                longPressSelection.target
                            } else {
                                findCustardVariation(key, "flick_variation", direction)
                            }
                            val pressActions = variation?.optJSONArray("press_actions")
                                ?: key.optJSONArray("press_actions")
                            val startIndex = if (continueDeleteVariationOnRelease) {
                                backwardWordDeleteContinuationStartIndex(pressActions) ?: 0
                            } else 0
                            dispatchActions(pressActions, startIndex)
                            feedback(target)
                        }
                    } else if (!didLongPress) {
                        val threshold = dp(20).toFloat() *
                            settings.optDouble("flick_sensitivity_setting", 1.0).toFloat()
                        val direction = if (!variationsEnabled || abs(dx) < threshold && abs(dy) < threshold) null
                        else if (abs(dx) > abs(dy)) if (dx < 0) "left" else "right"
                        else if (dy < 0) "top" else "bottom"
                        val variation = findCustardVariation(key, "flick_variation", direction)
                        dispatchActions(variation?.optJSONArray("press_actions") ?: key.optJSONArray("press_actions"))
                        feedback(target)
                    } else if (pcVariations.isNotEmpty() && activeRepeatActions.length() == 0) {
                        val width = target.width.coerceAtLeast(1)
                        val normalized = ((event.x / width) * pcVariations.size).toInt()
                        dispatchActions(
                            pcVariations[normalized.coerceIn(0, pcVariations.lastIndex)]
                                .optJSONObject("key")
                                ?.optJSONArray("press_actions"),
                        )
                    }
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val direction = flickDirection(event.x - startX, event.y - startY)
                    updateFlickGuide(direction)
                    if (
                        longPressSelection.update(direction) {
                            findCustardVariation(key, "flick_variation", it)
                        }
                    ) {
                        // azooKey cancels the center long-press as soon as a
                        // flick direction is selected, then reserves the
                        // variation's own long-press from that point.
                        handler.removeCallbacks(longPress)
                        val variationPressActions = longPressSelection.target
                            ?.optJSONArray("press_actions")
                        when (
                            firedLongPressTransition(
                                didLongPress = didLongPress,
                                variationDidLongPress = variationDidLongPress,
                                canRollbackCenter = centerLongPressCheckpoint != null,
                                canContinueAfterCenterDelete = canContinueDeleteLongPressIntoVariation(
                                    startActions,
                                    longPressData.optJSONArray("repeat") ?: JSONArray(),
                                    variationPressActions,
                                ),
                            )
                        ) {
                            FiredLongPressTransition.KEEP_CENTER -> {
                                // The first action cannot be reversed safely. Once
                                // it fires, keep it as the result instead of also
                                // dispatching a flick action.
                                return@setOnTouchListener true
                            }
                            FiredLongPressTransition.ROLLBACK_CENTER -> {
                                restoreComposition(checkNotNull(centerLongPressCheckpoint))
                                centerLongPressCheckpoint = null
                                longPressFlicked = true
                                didLongPress = false
                                repeating = false
                                handler.removeCallbacks(repeatAction)
                            }
                            FiredLongPressTransition.CONTINUE_AFTER_CENTER_DELETE -> {
                                // A delete key can begin its light long press before
                                // a slower flick crosses the threshold. Keep that
                                // first delete and run the remaining variation
                                // actions when the finger is released.
                                continueDeleteVariationOnRelease = true
                                centerLongPressCheckpoint = null
                                longPressFlicked = true
                                didLongPress = false
                                repeating = false
                                handler.removeCallbacks(repeatAction)
                            }
                            FiredLongPressTransition.CONTINUE -> {
                                if (didLongPress) {
                                    longPressFlicked = true
                                    didLongPress = false
                                    repeating = false
                                    handler.removeCallbacks(repeatAction)
                                }
                            }
                        }
                        val variationLongPress = longPressSelection.target?.optJSONObject("longpress_actions")
                        val hasVariationLongPress = (variationLongPress?.optJSONArray("start")?.length() ?: 0) > 0 ||
                            (variationLongPress?.optJSONArray("repeat")?.length() ?: 0) > 0
                        if (hasVariationLongPress) {
                            // Each flick variation owns its duration independently
                            // from the center key's long-press duration.
                            handler.postDelayed(longPress, longPressDelay(variationLongPress?.optString("duration")))
                        }
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(longPress)
                    repeating = false
                    handler.removeCallbacks(repeatAction)
                    centerLongPressCheckpoint = null
                    target.isPressed = false
                    dismissFlickGuide()
                    true
                }
                else -> true
            }
        }
        return view
    }

    private fun createCustardSystemKey(type: String, scale: Double): View {
        val customTarget = when (type) {
            "flick_kogaki" -> "kogana"
            "flick_kutoten" -> "kana_symbols"
            "flick_hira_tab" -> "hira_tab"
            "flick_abc_tab" -> "abc_tab"
            "flick_star123_tab" -> "symbols_tab"
            else -> null
        }
        customTarget?.let(::customKeyForTarget)?.let { return createCustomKey(it, scale) }
        return when (type) {
            "change_keyboard" -> createKey("🌐", true, scale) { nextKeyboard() }
            "qwerty_language_switch" -> createKey("あA", true, scale) {
                setMode(if (mode == "japanese") "english" else "japanese")
            }
            "qwerty_shift" -> createKey(if (capsLock) "⇪" else "⇧", true, scale) { toggleShift() }
            "qwerty_dynamic_change" -> createKey("☆123", true, scale) {
                if (mode == "symbols") setMode("english") else setMode("symbols")
            }
            "qwerty_space" -> createKey(if (composing.isEmpty()) "空白" else "次候補", false, scale) {
                if (candidates.isEmpty()) space() else {
                    selectedCandidate = (selectedCandidate + 1) % candidates.size
                    currentInputConnection?.setComposingText(candidates[selectedCandidate], 1)
                    renderCandidateValues()
                }
            }
            "enter" -> createKey("改行", true, scale) { enter() }
            "upper_lower" -> createKey("Aa", true, scale) {
                if (mode == "english") toggleShift() else transformLastCharacter()
            }
            "next_candidate" -> createKey(if (composing.isEmpty()) "空白" else "次候補", true, scale) {
                if (candidates.isEmpty()) space() else {
                    selectedCandidate = (selectedCandidate + 1) % candidates.size
                    currentInputConnection?.setComposingText(candidates[selectedCandidate], 1)
                    renderCandidateValues()
                }
            }
            "flick_kogaki" -> createFlickKey(FlickKey("小ﾞﾟ", action = "kogana", special = true), scale)
            "flick_kutoten" -> createFlickKey(FlickKey("､｡?!", "、", "。", "？", "！", null), scale)
            "flick_hira_tab" -> createKey("あいう", true, scale) { setMode("japanese") }
            "flick_abc_tab" -> createKey("ABC", true, scale) { setMode("english") }
            "flick_star123_tab" -> createKey("☆123", true, scale) { setMode("symbols") }
            else -> createKey("", true, scale) {}
        }
    }

    private fun custardLabel(label: JSONObject?): String {
        if (label == null) return ""
        if (label.has("text")) return label.optString("text")
        if (label.has("system_image")) return custardSystemImageLabel(label.optString("system_image"))
        return when (label.optString("type")) {
            "main_and_sub" -> "${label.optString("main")}\n${label.optString("sub")}"
            "main_and_directions" -> label.optString("main")
            "system_image" -> custardSystemImageLabel(label.optString("system_image"))
            else -> label.optString("text")
        }
    }

    private fun custardDirectionLabel(label: JSONObject?, direction: String): String? {
        if (label?.optString("type") != "main_and_directions") return null
        return label.optJSONObject("directions")
            ?.optString(direction)
            ?.takeIf(String::isNotEmpty)
    }

    private fun actionDisplayLabel(action: JSONObject?): String? {
        if (action == null) return null
        return when (action.optString("type", "input")) {
            "input" -> if (action.has("text")) action.optString("text") else action.optString("value")
            "directInput" -> action.optString("value")
            "direct_input" -> action.optString("text")
            else -> null
        }?.takeIf(String::isNotEmpty)
    }

    private fun findCustardVariation(key: JSONObject, type: String, direction: String?): JSONObject? {
        val normalizedDirection = custardFlickDirection(direction) ?: return null
        return custardVariations(key, type).firstOrNull { it.optString("direction") == normalizedDirection }
            ?.optJSONObject("key")
    }

    private fun custardVariations(key: JSONObject, type: String): List<JSONObject> {
        val values = key.optJSONArray("variations") ?: return emptyList()
        return (0 until values.length()).mapNotNull(values::optJSONObject)
            .filter { it.optString("type") == type }
    }

    private fun renderStandaloneCustomKeys(scale: Double) {
        val keys = state.optJSONArray("customKeys") ?: return
        val standalone = (0 until keys.length()).mapNotNull(keys::optJSONObject)
            .filter { it.optString("target", "standalone") == "standalone" }
            .take(8)
        if (standalone.isEmpty()) return
        for (start in standalone.indices step 4) {
            val row = newRow(scale)
            for (index in start until minOf(start + 4, standalone.size)) {
                row.addView(createCustomKey(standalone[index], scale), weightParams())
            }
            while (row.childCount < 4) row.addView(View(this), weightParams())
            keyboardContainer.addView(row)
        }
    }

    private fun customKeyForTarget(target: String): JSONObject? {
        val keys = state.optJSONArray("customKeys") ?: return null
        for (index in 0 until keys.length()) {
            val key = keys.optJSONObject(index) ?: continue
            if (key.optString("target", "standalone") == target) return key
        }
        return null
    }

    private fun createCustomKey(key: JSONObject, scale: Double): View {
        val centerLabel = key.optString("label", key.optString("name", ""))
        val leftLabel = actionDisplayLabel(key.optJSONObject("left"))
        val upLabel = actionDisplayLabel(key.optJSONObject("up"))
        val rightLabel = actionDisplayLabel(key.optJSONObject("right"))
        val downLabel = actionDisplayLabel(key.optJSONObject("down"))
        val view = if (listOf(leftLabel, upLabel, rightLabel, downLabel).any { !it.isNullOrEmpty() }) {
            createDirectionalKey(centerLabel, leftLabel, upLabel, rightLabel, downLabel, special = false)
        } else {
            createKey(centerLabel, false, scale, null)
        }
        val handler = Handler(Looper.getMainLooper())
        var startX = 0f
        var startY = 0f
        var longPressed = false
        var repeating = false
        var longPressFlicked = false
        val repeatAction = object : Runnable {
            override fun run() {
                if (!repeating) return
                dispatchAction(key.optJSONObject("longPressRepeat"))
                handler.postDelayed(this, 70)
            }
        }
        val longPress = Runnable {
            val action = key.optJSONObject("longPress")
            val repeated = key.optJSONObject("longPressRepeat")
            if (action == null && repeated == null) return@Runnable
            longPressed = true
            dismissFlickGuide()
            dispatchAction(action)
            if (repeated != null) {
                repeating = true
                handler.postDelayed(repeatAction, 70)
            }
            feedback(view)
        }
        view.setOnTouchListener { target, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.x
                    startY = event.y
                    longPressed = false
                    longPressFlicked = false
                    target.isPressed = true
                    val delay = longPressDelay(key.optString("longPressDuration", key.optString("duration")))
                    handler.postDelayed(longPress, delay)
                    runCatching {
                        showFlickGuide(
                            target,
                            key.optString("label", key.optString("name", "")),
                            leftLabel,
                            upLabel,
                            rightLabel,
                            downLabel,
                        )
                    }
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val direction = flickDirection(event.x - startX, event.y - startY)
                    if (direction != null) {
                        handler.removeCallbacks(longPress)
                        if (longPressed) {
                            longPressFlicked = true
                            longPressed = false
                            repeating = false
                            handler.removeCallbacks(repeatAction)
                        }
                    }
                    updateFlickGuide(direction)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    handler.removeCallbacks(longPress)
                    repeating = false
                    handler.removeCallbacks(repeatAction)
                    target.isPressed = false
                    dismissFlickGuide()
                    if (!longPressed || longPressFlicked) {
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
                        runCatching {
                            dispatchAction(key.optJSONObject(direction) ?: key.optJSONObject("tap"))
                        }
                        feedback(target)
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(longPress)
                    repeating = false
                    handler.removeCallbacks(repeatAction)
                    target.isPressed = false
                    dismissFlickGuide()
                    true
                }
                else -> true
            }
        }
        return view
    }

    private fun createFlickKey(key: FlickKey, scale: Double): View {
        val view = createKey(key.label, key.special, scale, null)
        val handler = Handler(Looper.getMainLooper())
        var startX = 0f
        var startY = 0f
        var longPressed = false
        var repeating = false
        var longPressFlicked = false
        var textDragSession: TextSelectionSession? = null
        var textDragStep = 0
        var textDragMoved = false
        val isDelete = key.action == "delete"
        val isSpace = key.action == "space"
        val repeat = object : Runnable {
            override fun run() {
                if (!repeating) return
                if (isDelete) delete() else if (isSpace) selectNextCandidate()
                handler.postDelayed(this, 70)
            }
        }
        val longPress = Runnable {
            if (!isDelete && !isSpace) return@Runnable
            longPressed = true
            if (composing.isEmpty() && rawRoman.isEmpty()) {
                textDragSession = TextSelectionSession.capture(currentInputConnection)
                textDragStep = 0
                textDragMoved = false
                if (textDragSession == null) {
                    if (isDelete) delete() else toggleCursorBar()
                }
            } else if (isDelete) {
                repeating = true
                delete()
                handler.postDelayed(repeat, 70)
            } else {
                repeating = true
                selectNextCandidate()
                handler.postDelayed(repeat, 70)
            }
            feedback(view)
        }
        view.setOnTouchListener { target, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.x
                    startY = event.y
                    longPressed = false
                    repeating = false
                    longPressFlicked = false
                    textDragSession = null
                    textDragStep = 0
                    textDragMoved = false
                    if (isDelete || isSpace) handler.postDelayed(longPress, longPressDelay())
                    target.isPressed = true
                    showFlickGuide(target, key.label, key.left, key.up, key.right, key.down)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    textDragSession?.let { session ->
                        val step = ((event.x - startX) / dp(18).toFloat()).roundToInt()
                        if (step != textDragStep) {
                            val changed = if (isDelete) session.select(step) else session.moveCursor(step)
                            if (changed) {
                                textDragStep = step
                                textDragMoved = textDragMoved || step != 0
                                feedback(target)
                                cursorBarView?.post { cursorBarView?.refresh() }
                            }
                        }
                        updateFlickGuide(
                            when {
                                step < 0 -> "left"
                                step > 0 -> "right"
                                else -> null
                            },
                        )
                        return@setOnTouchListener true
                    }
                    val direction = flickDirection(event.x - startX, event.y - startY)
                    if (direction != null) {
                        handler.removeCallbacks(longPress)
                        if (longPressed) {
                            longPressFlicked = true
                            longPressed = false
                            repeating = false
                            handler.removeCallbacks(repeat)
                        }
                    }
                    updateFlickGuide(direction)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    handler.removeCallbacks(longPress)
                    repeating = false
                    handler.removeCallbacks(repeat)
                    target.isPressed = false
                    textDragSession?.let { session ->
                        if (isDelete && textDragMoved) {
                            session.deleteSelection()
                        } else if (!textDragMoved) {
                            if (isDelete) delete() else toggleCursorBar()
                        }
                        textDragSession = null
                        dismissFlickGuide()
                        return@setOnTouchListener true
                    }
                    val dx = event.x - startX
                    val dy = event.y - startY
                    val direction = flickDirection(dx, dy)
                    val value = when (direction) {
                        "left" -> key.left
                        "up" -> key.up
                        "right" -> key.right
                        "down" -> key.down
                        else -> key.center
                    }
                    dismissFlickGuide()
                    if (!longPressed || longPressFlicked) {
                        if (isSpace && direction == "left") {
                            moveCursor(-1)
                        } else if (isSpace && direction == "right") {
                            moveCursor(1)
                        } else if (isSpace && direction == "up") {
                            inputText("　")
                        } else if (isSpace && direction == "down") {
                            inputText("\t")
                        } else if (isDelete && direction == "left") {
                            smartDeleteDefault()
                        } else if (key.action != null) {
                            dispatchNamedAction(key.action)
                        } else {
                            inputText(value ?: key.center)
                        }
                        feedback(target)
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(longPress)
                    repeating = false
                    handler.removeCallbacks(repeat)
                    textDragSession?.cancel()
                    textDragSession = null
                    target.isPressed = false
                    dismissFlickGuide()
                    true
                }
                else -> true
            }
        }
        return view
    }

    private fun showFlickGuide(
        target: View,
        center: String,
        left: String?,
        up: String?,
        right: String?,
        down: String?,
    ) {
        dismissFlickGuide()
        if (listOf(left, up, right, down).all { it.isNullOrEmpty() }) return
        val cellWidth = target.width.coerceAtLeast(1)
        val cellHeight = target.height.coerceAtLeast(1)
        val content = FrameLayout(this)
        val directionCells = mutableMapOf<String, TextView>()
        var centerCell: TextView? = null

        fun addCell(label: String?, column: Int, row: Int, direction: String?, selected: Boolean = false) {
            if (label.isNullOrEmpty()) return
            val cell = flickGuideCell(label, selected)
            val gap = dp(1)
            content.addView(
                cell,
                FrameLayout.LayoutParams(
                    (cellWidth - gap * 2).coerceAtLeast(1),
                    (cellHeight - gap * 2).coerceAtLeast(1),
                ).apply {
                    leftMargin = column * cellWidth + gap
                    topMargin = row * cellHeight + gap
                },
            )
            if (direction == null) centerCell = cell else directionCells[direction] = cell
        }

        addCell(up, 1, 0, "up")
        addCell(left, 0, 1, "left")
        addCell(center, 1, 1, null, selected = true)
        addCell(right, 2, 1, "right")
        addCell(down, 1, 2, "down")

        val targetLocation = IntArray(2)
        val inputWindowLocation = IntArray(2)
        target.getLocationOnScreen(targetLocation)
        inputViewFrame.getLocationOnScreen(inputWindowLocation)
        val guideWidth = cellWidth * 3
        val guideHeight = cellHeight * 3
        // PopupWindow offsets are relative to the IME window, while
        // getLocationOnScreen() returns display coordinates. Passing the
        // display Y coordinate here moves the guide down by the IME window's
        // top offset (several key rows on a phone).
        // inputViewFrame continues to span the IME window in one-handed mode,
        // while root itself moves left or right. Use the window origin so the
        // guide stays attached to the pressed key in every width mode.
        val targetLeftInWindow = targetLocation[0] - inputWindowLocation[0]
        val targetTopInWindow = targetLocation[1] - inputWindowLocation[1]
        val guideLeft = targetLeftInWindow - cellWidth
        val guideTop = targetTopInWindow - cellHeight
        val popup = PopupWindow(content, guideWidth, guideHeight, false).apply {
            isTouchable = false
            isFocusable = false
            isOutsideTouchable = false
            isClippingEnabled = false
            inputMethodMode = PopupWindow.INPUT_METHOD_NOT_NEEDED
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) elevation = dp(5).toFloat()
            showAtLocation(root, Gravity.TOP or Gravity.START, guideLeft, guideTop)
        }
        flickGuide = FlickGuide(popup, checkNotNull(centerCell), directionCells)
    }

    private fun flickGuideCell(label: String, selected: Boolean): TextView = TextView(this).apply {
        text = label
        gravity = Gravity.CENTER
        includeFontPadding = false
        setTextColor(if (selected) Color.WHITE else palette.text)
        textSize = keyTextSize(label)
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
        background = roundedDrawable(if (selected) palette.accent else palette.key, dp(6).toFloat())
    }

    private fun updateFlickGuide(direction: String?) {
        val guide = flickGuide ?: return
        guide.centerCell.setTextColor(if (direction == null) Color.WHITE else palette.text)
        guide.centerCell.background = roundedDrawable(
            if (direction == null) palette.accent else palette.key,
            dp(6).toFloat(),
        )
        for ((cellDirection, cell) in guide.directionCells) {
            val selected = cellDirection == direction
            cell.setTextColor(if (selected) Color.WHITE else palette.text)
            cell.background = roundedDrawable(if (selected) palette.accent else palette.key, dp(6).toFloat())
        }
    }

    private fun dismissFlickGuide() {
        flickGuide?.popup?.dismiss()
        flickGuide = null
    }

    private fun flickDirection(dx: Float, dy: Float): String? {
        val threshold = dp(20).toFloat() *
            settings.optDouble("flick_sensitivity_setting", 1.0).toFloat()
        if (abs(dx) < threshold && abs(dy) < threshold) return null
        return if (abs(dx) > abs(dy)) {
            if (dx < 0) "left" else "right"
        } else {
            if (dy < 0) "up" else "down"
        }
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
            textSize = if (textSizeSetting > 0) textSizeSetting.toFloat() else keyTextSize(label)
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
            isAllCaps = false
            background = roundedDrawable(if (special) palette.special else palette.key, dp(6).toFloat())
            val vertical = (dp(2) * scale).toInt().coerceAtLeast(1)
            val horizontal = dp(2)
            setPadding(horizontal, vertical, horizontal, vertical)
            if (action != null && (label == "⌫" || label == "space" || label == "空白" || label == "次候補")) {
                // azooKey's delete and space keys share the same long-press
                // state machine. Space opens the cursor bar when no candidate
                // is active, otherwise it repeats candidate selection.
                val isDelete = label == "⌫"
                val isNextCandidate = label == "次候補"
                val handler = Handler(Looper.getMainLooper())
                var longPressed = false
                var repeating = false
                var textDragSession: TextSelectionSession? = null
                var textDragStep = 0
                var textDragMoved = false
                var textDragStartX = 0f
                val repeat = object : Runnable {
                    override fun run() {
                        if (!repeating) return
                        if (isDelete) action() else if (isNextCandidate) space() else selectNextCandidate()
                        handler.postDelayed(this, 70)
                    }
                }
                val longPress = Runnable {
                    longPressed = true
                    if (!isNextCandidate && composing.isEmpty() && rawRoman.isEmpty()) {
                        textDragSession = TextSelectionSession.capture(currentInputConnection)
                        textDragStep = 0
                        textDragMoved = false
                        repeating = false
                        if (textDragSession == null) {
                            if (isDelete) action() else toggleCursorBar()
                        }
                    } else if (isDelete) {
                        repeating = true
                        action()
                        handler.postDelayed(repeat, 70)
                    } else if (isNextCandidate) {
                        repeating = false
                        space()
                    } else if (composing.isEmpty() && rawRoman.isEmpty()) {
                        repeating = false
                        toggleCursorBar()
                    } else {
                        selectNextCandidate()
                        handler.postDelayed(repeat, 70)
                    }
                    feedback(this@apply)
                }
                setOnTouchListener { target, event ->
                    when (event.actionMasked) {
                        MotionEvent.ACTION_DOWN -> {
                            textDragStartX = event.x
                            longPressed = false
                            repeating = false
                            textDragSession = null
                            textDragStep = 0
                            textDragMoved = false
                            handler.postDelayed(longPress, longPressDelay())
                            target.isPressed = true
                            true
                        }
                        MotionEvent.ACTION_MOVE -> {
                            textDragSession?.let { session ->
                                val step = ((event.x - textDragStartX) / dp(18).toFloat()).roundToInt()
                                if (step != textDragStep) {
                                    val changed = if (isDelete) session.select(step) else session.moveCursor(step)
                                    if (changed) {
                                        textDragStep = step
                                        textDragMoved = textDragMoved || step != 0
                                        feedback(target)
                                        cursorBarView?.post { cursorBarView?.refresh() }
                                    }
                                }
                            }
                            true
                        }
                        MotionEvent.ACTION_UP -> {
                            handler.removeCallbacks(longPress)
                            repeating = false
                            handler.removeCallbacks(repeat)
                            target.isPressed = false
                            textDragSession?.let { session ->
                                if (isDelete && textDragMoved) {
                                    session.deleteSelection()
                                } else if (!textDragMoved) {
                                    if (isDelete) action() else toggleCursorBar()
                                }
                                textDragSession = null
                                return@setOnTouchListener true
                            }
                            if (!longPressed) {
                                action()
                                feedback(target)
                            }
                            true
                        }
                        MotionEvent.ACTION_CANCEL -> {
                            handler.removeCallbacks(longPress)
                            repeating = false
                            handler.removeCallbacks(repeat)
                            textDragSession?.cancel()
                            textDragSession = null
                            target.isPressed = false
                            true
                        }
                        else -> true
                    }
                }
            } else if (action != null) {
                setOnClickListener {
                    action()
                    feedback(this)
                }
            }
        }
    }

    private fun createDirectionalKey(
        center: String,
        left: String?,
        up: String?,
        right: String?,
        down: String?,
        special: Boolean,
    ): DirectionalKeyView {
        val configuredSize = settings.optDouble("key_view_font_size", -1.0)
        val centerSize = if (configuredSize > 0) configuredSize.toFloat() else keyTextSize(center)
        val longestDirection = listOfNotNull(left, up, right, down).maxOfOrNull(String::length) ?: 1
        val directionSize = if (configuredSize > 0) {
            (configuredSize * 0.62).toFloat().coerceAtLeast(8f)
        } else if (longestDirection > 2) {
            8f
        } else {
            10f
        }
        return DirectionalKeyView(
            context = this,
            center = center,
            left = left,
            up = up,
            right = right,
            down = down,
            textColor = palette.text,
            centerTextSize = centerSize,
            directionTextSize = directionSize,
        ).apply {
            background = roundedDrawable(if (special) palette.special else palette.key, dp(6).toFloat())
        }
    }

    private fun custardPrimaryLabel(label: JSONObject?): String {
        if (label == null) return ""
        return when (label.optString("type")) {
            "main_and_sub", "main_and_directions" -> label.optString("main")
            else -> custardLabel(label)
        }
    }

    private fun keyTextSize(label: String): Float = if (label.length > 3) 11f else 17f

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
            cursorBarVisible = false
            cursorBarView = null
        }
        if (cursorBarVisible) {
            renderCursorBar()
            return
        }
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
                background = roundedDrawable(palette.key, dp(6).toFloat())
                setOnClickListener { commitCandidate(index) }
                setOnLongClickListener {
                    showLegacyReportPrompt(candidate, index)
                    true
                }
            }, candidateButtonLayoutParams())
        }
    }

    private fun renderTabBar() {
        val values = resolvedTabBar()
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
                background = roundedDrawable(palette.key, dp(6).toFloat())
                isClickable = true
                isFocusable = false
                if (value.startsWith("custom:")) {
                    setOnTouchListener { _, event ->
                        if (event.actionMasked == MotionEvent.ACTION_UP) selectTab(value)
                        true
                    }
                } else {
                    setOnClickListener { selectTab(value) }
                }
            }, candidateButtonLayoutParams())
        }
        if (settings.optBoolean("enable_clipboard_history_manager_tab", false) &&
            (0 until values.length()).none { values.optString(it) == "clipboard" }
        ) {
            candidateRow.addView(TextView(this).apply {
                text = "📋"
                gravity = Gravity.CENTER
                setTextColor(palette.text)
                setPadding(dp(16), 0, dp(16), 0)
                background = roundedDrawable(palette.key, dp(6).toFloat())
                setOnClickListener { showClipboardHistory() }
            }, candidateButtonLayoutParams())
        }
    }

    private fun toggleCursorBar() {
        cursorBarVisible = !cursorBarVisible
        if (cursorBarVisible) {
            renderCursorBar()
            if (settings.optBoolean("display_cursor_bar_automatically", false)) {
                cursorBarView?.scheduleAutoDismiss()
            }
        } else {
            cursorBarView = null
            renderCandidates()
        }
    }

    private fun renderCursorBar() {
        if (!::candidateRow.isInitialized) return
        candidateRow.removeAllViews()
        val bar = CursorBarView()
        cursorBarView = bar
        candidateRow.addView(
            bar,
            LinearLayout.LayoutParams(resources.displayMetrics.widthPixels, dp(43)),
        )
        bar.post { bar.refresh() }
    }

    private fun resolvedTabBar(): JSONArray {
        val configured = state.optJSONArray("tabBar") ?: JSONArray(
            listOf("dismiss", "resize", "emoji", "japanese", "english"),
        )
        val customItems = linkedSetOf<String>()
        val tabs = state.optJSONArray("customTabs") ?: JSONArray()
        for (index in 0 until tabs.length()) {
            val tab = tabs.optJSONObject(index) ?: continue
            if (!tab.optBoolean("addToTabBar", true)) continue
            val id = tab.optString("id").trim()
            if (id.isNotEmpty()) customItems.add("custom:$id")
        }
        val custards = state.optJSONArray("custards") ?: JSONArray()
        for (index in 0 until custards.length()) {
            val id = custards.optJSONObject(index)?.optString("identifier").orEmpty()
            if (id.isNotEmpty()) customItems.add("custom:$id")
        }

        val resolved = JSONArray()
        val included = mutableSetOf<String>()
        for (index in 0 until configured.length()) {
            val value = configured.optString(index)
            if (value.startsWith("custom:") && value !in customItems) continue
            if (value.isNotEmpty() && included.add(value)) resolved.put(value)
        }
        for (value in customItems) {
            if (included.add(value)) resolved.put(value)
        }
        return resolved
    }

    private fun selectTab(value: String) {
        when {
            value == "dismiss" -> requestHideSelf(0)
            value == "emoji" -> showEmoji()
            value == "japanese" -> setMode("japanese")
            value == "english" -> setMode("english")
            value == "clipboard" -> showClipboardHistory()
            value.startsWith("custom:") -> {
                commitComposition()
                activeCustomTab = value.removePrefix("custom:").trim()
                getSharedPreferences(MainActivity.PREFERENCES_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putString(ACTIVE_CUSTOM_TAB_KEY, activeCustomTab)
                    .apply()
                mode = "japanese"
                layout = "flick"
                renderKeyboard()
            }
            value == "resize" -> showResizeControls()
        }
    }

    private fun showResizeControls() {
        candidateRow.removeAllViews()
        addCandidateButton(if (oneHandedMode == "left") "✓ 左寄せ" else "← 左寄せ") {
            setOneHandedMode("left")
        }
        addCandidateButton(if (oneHandedMode == "full") "✓ 標準" else "↔ 標準") {
            setOneHandedMode("full")
        }
        addCandidateButton(if (oneHandedMode == "right") "✓ 右寄せ" else "右寄せ →") {
            setOneHandedMode("right")
        }
        addCandidateButton("閉じる") { renderCandidates() }
    }

    private fun setOneHandedMode(value: String) {
        oneHandedMode = value
        getSharedPreferences(MainActivity.PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(ONE_HANDED_MODE_KEY, value)
            .apply()
        applyKeyboardWidth()
        showResizeControls()
    }

    private fun applyKeyboardWidth() {
        if (!::root.isInitialized) return
        val width = if (oneHandedMode == "full") {
            FrameLayout.LayoutParams.MATCH_PARENT
        } else {
            (resources.displayMetrics.widthPixels * 0.78f).toInt()
        }
        val horizontalGravity = when (oneHandedMode) {
            "left" -> Gravity.START
            "right" -> Gravity.END
            else -> Gravity.CENTER_HORIZONTAL
        }
        root.layoutParams = FrameLayout.LayoutParams(
            width,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            horizontalGravity or Gravity.BOTTOM,
        )
        backgroundImageView.layoutParams = FrameLayout.LayoutParams(
            width,
            FrameLayout.LayoutParams.MATCH_PARENT,
            horizontalGravity or Gravity.BOTTOM,
        )
        root.requestLayout()
        backgroundImageView.requestLayout()
        inputViewFrame.requestLayout()
    }

    private fun customTabName(id: String): String {
        val tabs = state.optJSONArray("customTabs") ?: JSONArray()
        for (index in 0 until tabs.length()) {
            val tab = tabs.optJSONObject(index) ?: continue
            if (tab.optString("id") == id) return tab.optString("name", "タブ")
        }
        val custards = state.optJSONArray("custards") ?: JSONArray()
        for (index in 0 until custards.length()) {
            val custard = custards.optJSONObject(index) ?: continue
            if (custard.optString("identifier") == id) {
                return custard.optJSONObject("metadata")?.optString("display_name", "タブ") ?: "タブ"
            }
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
            background = roundedDrawable(palette.key, dp(6).toFloat())
            setOnClickListener { action() }
        }, candidateButtonLayoutParams())
    }

    private fun candidateButtonLayoutParams() = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.WRAP_CONTENT,
        dp(43),
    ).apply {
        setMargins(dp(2), 0, dp(2), 0)
    }

    private fun inputText(value: String?) {
        if (value.isNullOrEmpty()) return
        if (mode == "english") {
            inputEnglishText(value)
            return
        }
        if (shouldDirectCommitJapaneseInput(value)) {
            directCommit(value)
            return
        }
        if (layout == "qwerty") rawRoman += value.lowercase() else composing += value
        updateComposition()
    }

    private fun inputEnglishText(value: String) {
        val resolved = if (shift || capsLock) value.uppercase(Locale.ROOT) else value
        if (resolved.all { it in 'a'..'z' || it in 'A'..'Z' }) {
            composing += resolved
            updateComposition()
        } else {
            directCommit(resolved)
        }
        if (shift && !capsLock) {
            shift = false
            renderKeyboard()
        }
    }

    private fun updateComposition() {
        val reading = displayReading()
        if (mode != "english" && layout == "qwerty") composing = reading
        selectedCandidate = 0
        candidates = buildCandidates().toMutableList()
        if (candidates.isEmpty() && reading.isNotEmpty()) candidates.add(reading)
        val live = settings.optBoolean("live_conversion", true)
        val displayed = if (mode == "english") {
            reading
        } else if (live && candidates.isNotEmpty()) {
            candidates.first()
        } else {
            reading
        }
        currentInputConnection?.setComposingText(displayed, 1)
        renderCandidateValues()
        requestZenzaiCandidates(reading, candidates.toList())
    }

    private fun requestZenzaiCandidates(reading: String, baseCandidates: List<String>) {
        if (mode != "japanese" ||
            !settings.optBoolean("enable_zenzai", true) ||
            reading.isBlank() ||
            shouldDirectCommitJapaneseInput(reading)
        ) return
        val effort = settings.optInt("zenzai_effort", 1).coerceIn(0, 2)
        val size = if (effort == 0) "xsmall" else "small"
        val modelInput = hiraganaToKatakana(reading)
        val effortTokenLimit = when (effort) {
            0 -> 24
            2 -> 48
            else -> 32
        }
        val maxTokens = (modelInput.length * 2 + 6).coerceIn(8, effortTokenLimit)
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
            reading = modelInput,
            leftContext = leftContext,
            rightContext = rightContext,
            baseCandidates = baseCandidates,
            maxTokens = maxTokens,
        ) { ranked ->
            if (displayReading() != reading || ranked.isEmpty()) return@rank
            val liveCandidate = if (settings.optBoolean("live_conversion", true)) {
                ranked.firstOrNull()
            } else {
                null
            }
            candidates = pinJapaneseKanaCandidates(
                reading = reading,
                ranked = ranked,
                liveCandidate = liveCandidate,
            ).toMutableList()
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
        if (mode == "english") return buildEnglishCandidates(reading)
        if (shouldDirectCommitJapaneseInput(reading)) return listOf(reading)
        val values = linkedSetOf<String>()
        val dictionary = state.optJSONArray("userDictionary") ?: JSONArray()
        val predictedValues = linkedSetOf<String>()
        // Prefix predictions are independent from automatic commit strength.
        // A user who disables automatic commit must still see completions while
        // composing a word.
        val predictionLimit = PREDICTION_LIMIT
        val userEntries = (0 until dictionary.length()).mapNotNull(dictionary::optJSONObject)
            .sortedByDescending { it.optInt("importance", 3).coerceIn(1, 5) }
        for (entry in userEntries) {
            val ruby = entry.optString("ruby")
            val value = if (entry.optBoolean("isTemplateMode", false)) {
                renderTemplate(entry.optString("formatLiteral", entry.optString("word")))
            } else {
                entry.optString("word")
            }
            if (ruby == reading) values.add(value)
            else if (predictionLimit > 0 && ruby.startsWith(reading)) predictedValues.add(value)
        }
        val officialCandidates = runCatching {
            azooKeyDictionary.candidates(
                reading,
                predictionLimit,
                additionalEntries = hotfixDictionaryEntries,
                additionalDictionaryVersion = hotfixDictionaryVersion,
            )
        }.onFailure {
            Log.e("AzooKeyDictionary", "Failed to read the bundled dictionary", it)
        }.getOrElse {
            DictionaryCandidates(emptyList(), emptyList())
        }
        values.addAll(officialCandidates.conversions)
        if (officialCandidates.conversions.isEmpty()) {
            systemDictionary[reading]?.let(values::addAll)
        }
        values.add(reading)
        if (predictionLimit > 0) {
            predictedValues.addAll(
                prefixPredictionValues(
                    reading,
                    systemDictionary.map { (ruby, predictions) -> ruby to predictions },
                    predictionLimit,
                ),
            )
            predictedValues.addAll(officialCandidates.predictions)
            val prioritized = prioritizePrefixPredictions(
                conversions = values.toList(),
                predictions = predictedValues.take(predictionLimit),
                insertIndex = PREDICTION_INSERT_INDEX,
            )
            values.clear()
            values.addAll(prioritized)
        }
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
        val ranked = values.filter { it.isNotEmpty() }.withIndex().sortedWith(
            compareByDescending<IndexedValue<String>> {
                if (learningMode == 2) 0 else scores.optInt("$reading\t${it.value}", 0)
            }.thenBy { it.index },
        ).map { it.value }
        return pinJapaneseKanaCandidates(
            reading = reading,
            ranked = ranked,
            liveCandidate = if (settings.optBoolean("live_conversion", true)) ranked.firstOrNull() else null,
        )
    }

    private fun buildEnglishCandidates(input: String): List<String> {
        val prefix = input.lowercase(Locale.ROOT)
        val preferred = mutableListOf<String>()
        val dictionary = state.optJSONArray("userDictionary") ?: JSONArray()
        for (index in 0 until dictionary.length()) {
            val entry = dictionary.optJSONObject(index) ?: continue
            val ruby = entry.optString("ruby")
            val word = if (entry.optBoolean("isTemplateMode", false)) {
                renderTemplate(entry.optString("formatLiteral", entry.optString("word")))
            } else {
                entry.optString("word")
            }
            if (ruby.lowercase(Locale.ROOT).startsWith(prefix) ||
                word.lowercase(Locale.ROOT).startsWith(prefix)
            ) {
                preferred.add(word)
            }
        }

        val learned = mutableListOf<Pair<Int, String>>()
        val scores = state.optJSONObject("learning") ?: JSONObject()
        val keys = scores.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val separator = key.indexOf('\t')
            if (separator <= 0 || separator == key.lastIndex) continue
            val reading = key.substring(0, separator)
            val candidate = key.substring(separator + 1)
            if (reading.lowercase(Locale.ROOT).startsWith(prefix) ||
                candidate.lowercase(Locale.ROOT).startsWith(prefix)
            ) {
                learned.add(scores.optInt(key) to candidate)
            }
        }
        preferred.addAll(learned.sortedByDescending { it.first }.map { it.second })
        return englishPredictionCandidates(input, preferred, PREDICTION_LIMIT)
    }

    private fun commitCandidate(index: Int) {
        if (candidates.isEmpty()) return
        if (settings.optBoolean("enable_zenzai", true)) zenzaiRuntime.cancel()
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
        addCandidateButton("共有辞書へ改善を送信") { submitPendingReport() }
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
        addCandidateButton("改善を送信") { submitPendingReport() }
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
        addCandidateButton("共有辞書へ改善を送信") { submitPendingReport() }
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
        ReportClient.submitSharedConversionImprovement(
            endpoint = getSharedPreferences(MainActivity.PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getString(MainActivity.DICTIONARY_SUBMISSION_URL_KEY, "")
                .orEmpty(),
            report = report,
            appVersion = packageManager.getPackageInfo(packageName, 0).versionName ?: "Unknown Version",
        ) { success ->
            Handler(Looper.getMainLooper()).post {
                if (success) registerReportedPair(report)
                pendingReport = null
                candidateRow.removeAllViews()
                addCandidateButton(if (success) "変換の改善を送信しました" else "送信に失敗しました") {}
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
        if (settings.optBoolean("enable_zenzai", true)) zenzaiRuntime.cancel()
        val reading = displayReading()
        val availableCandidates = if (useCandidate) candidates.ifEmpty { buildCandidates() } else emptyList()
        val text = compositionCommitText(reading, availableCandidates, useCandidate)
        if (useCandidate) learnCandidate(reading, text)
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
        cursorBarView?.post { cursorBarView?.refresh() }
    }

    private fun clearComposition() {
        if (settings.optBoolean("enable_zenzai", true)) zenzaiRuntime.cancel()
        composing = ""
        rawRoman = ""
        selectedCandidate = 0
        candidates.clear()
        // finishComposingText() alone commits the visible composing candidate.
        // Replace it with an empty composition first so deletion is reflected
        // in the editor as well as in our internal buffers.
        currentInputConnection?.setComposingText("", 1)
        currentInputConnection?.finishComposingText()
        renderCandidates()
    }

    private fun delete() {
        when {
            layout == "qwerty" && rawRoman.isNotEmpty() -> {
                rawRoman = rawRoman.dropLast(1)
                composing = romanToHiragana(rawRoman)
                if (rawRoman.isEmpty()) {
                    clearComposition()
                } else updateComposition()
            }
            composing.isNotEmpty() -> {
                composing = composing.dropLast(1)
                if (composing.isEmpty()) {
                    clearComposition()
                } else updateComposition()
            }
            else -> {
                currentInputConnection?.deleteSurroundingText(1, 0)
                cursorBarView?.post { cursorBarView?.refresh() }
            }
        }
    }

    private fun deleteForward() {
        // The local composition cursor is always at its trailing edge, matching
        // azooKey's behavior: a forward delete has nothing to remove until the
        // composition is committed or cleared.
        if (composing.isNotEmpty() || rawRoman.isNotEmpty()) return
        currentInputConnection?.deleteSurroundingText(0, 1)
        cursorBarView?.post { cursorBarView?.refresh() }
    }

    private fun space() {
        if (composing.isEmpty() && rawRoman.isEmpty()) {
            currentInputConnection?.commitText(" ", 1)
        } else if (mode == "english") {
            commitComposition()
            currentInputConnection?.commitText(" ", 1)
        } else if (settings.optBoolean("use_next_candidate_key", false) && candidates.size > 1) {
            selectedCandidate = (selectedCandidate + 1) % candidates.size
            currentInputConnection?.setComposingText(candidates[selectedCandidate], 1)
            renderCandidates(false)
        } else {
            commitComposition()
        }
    }

    private fun spaceWithoutConversion() {
        commitComposition(useCandidate = false)
        currentInputConnection?.commitText(" ", 1)
        cursorBarView?.post { cursorBarView?.refresh() }
    }

    private fun selectNextCandidate() {
        if (candidates.isEmpty()) {
            space()
            return
        }
        selectedCandidate = (selectedCandidate + 1) % candidates.size
        currentInputConnection?.setComposingText(candidates[selectedCandidate], 1)
        renderCandidateValues()
    }

    private fun enter() {
        commitComposition()
        // This respects IME_FLAG_NO_ENTER_ACTION, which multiline editors such as
        // chat compose boxes use to request a newline instead of their send action.
        if (!sendDefaultEditorAction(true)) currentInputConnection?.commitText("\n", 1)
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
        getSharedPreferences(MainActivity.PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(ACTIVE_CUSTOM_TAB_KEY)
            .apply()
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
            "japanese" -> setMode("japanese")
            "english" -> setMode("english")
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
            "input" -> if (action.has("text")) custardInput(action.optString("text")) else directCommit(value)
            "directInput" -> directCommit(value)
            "direct_input" -> directCommit(action.optString("text"))
            "delete" -> {
                val count = if (action.has("count")) action.optInt("count", 1)
                else value.toIntOrNull() ?: 1
                val deletion = surroundingDeleteFor(count)
                repeat(deletion.beforeCursor) { delete() }
                repeat(deletion.afterCursor) { deleteForward() }
            }
            "enter" -> enter()
            "space" -> spaceWithoutConversion()
            "moveCursor" -> moveCursor(value.toIntOrNull() ?: 0)
            "move_cursor" -> moveCursor(action.optInt("count"))
            "switchLayout" -> setMode(if (value == "english") "english" else "japanese")
            "paste", "__paste" -> paste()
            "replace_default" -> replaceDefault()
            "replaceDefault" -> replaceDefault()
            "replace_last_characters" -> replaceLastCharacters(action.optJSONObject("table"))
            "smart_delete_default" -> smartDeleteDefault()
            "smartDeleteDefault" -> smartDeleteDefault()
            "smart_delete" -> smartDelete(action)
            "select_candidate" -> selectCandidate(action.optJSONObject("selection"))
            "complete_character_form" -> completeCharacterForm(action.optJSONArray("forms"))
            "completeCharacterForm" -> completeCharacterForm(JSONArray().put(value))
            "complete" -> commitComposition()
            "smart_move_cursor" -> smartMoveCursor(action)
            "move_tab" -> moveTab(action)
            "enable_resizing_mode" -> renderCandidates(true)
            "toggle_cursor_bar", "toggleCursorBar" -> toggleCursorBar()
            "toggleTabBar", "toggle_tab_bar" -> renderCandidates(true)
            "toggle_caps_lock_state" -> {
                capsLock = !capsLock
                shift = capsLock
                renderKeyboard()
            }
            "toggleCapsLock" -> {
                capsLock = !capsLock
                shift = capsLock
                renderKeyboard()
            }
            "dismiss", "dismiss_keyboard" -> requestHideSelf(0)
            "launch_application" -> launchApplication(action)
        }
    }

    private fun dispatchActions(actions: JSONArray?, startIndex: Int = 0) {
        if (actions == null) return
        var index = startIndex.coerceAtLeast(0)
        while (index < actions.length()) {
            val action = actions.optJSONObject(index)
            val next = actions.optJSONObject(index + 1)
            if (positiveBackwardDelete(action) && isBackwardSmartDelete(next)) {
                dispatchCombinedBackwardSmartDelete(checkNotNull(action), checkNotNull(next))
                index += 2
            } else {
                dispatchAction(action)
                index += 1
            }
        }
    }

    private fun positiveBackwardDelete(action: JSONObject?): Boolean {
        val value = action ?: return false
        if (value.optString("type") != "delete") return false
        val count = if (value.has("count")) value.optInt("count", 1)
        else value.optString("value").toIntOrNull() ?: 1
        return count > 0
    }

    private fun isBackwardSmartDelete(action: JSONObject?): Boolean {
        val value = action ?: return false
        return value.optString("type") == "smart_delete_default" ||
            (
                value.optString("type") == "smart_delete" &&
                    value.optString("direction", "forward") == "backward"
            )
    }

    private fun dispatchCombinedBackwardSmartDelete(
        deleteAction: JSONObject,
        smartDeleteAction: JSONObject,
    ) {
        val leadingCount = if (deleteAction.has("count")) {
            deleteAction.optInt("count", 1)
        } else {
            deleteAction.optString("value").toIntOrNull() ?: 1
        }
        val targets = if (smartDeleteAction.optString("type") == "smart_delete_default") {
            defaultScanTargets
        } else {
            actionTargets(smartDeleteAction)
        }
        if (composing.isNotEmpty() || rawRoman.isNotEmpty()) {
            if (
                rawRoman.isNotEmpty() ||
                smartDeleteAction.optString("type") == "smart_delete_default"
            ) {
                clearComposition()
                return
            }
            val count = combinedBackwardSmartDeleteCount(composing, leadingCount, targets)
            composing = composing.dropLast(count.coerceAtMost(composing.length))
            if (composing.isEmpty()) clearComposition() else updateComposition()
            return
        }
        val text = currentInputConnection
            ?.getTextBeforeCursor(2000, 0)
            ?.toString()
            .orEmpty()
        val count = combinedBackwardSmartDeleteCount(text, leadingCount, targets)
        if (count > 0) currentInputConnection?.deleteSurroundingText(count, 0)
        cursorBarView?.post { cursorBarView?.refresh() }
    }

    private fun backwardWordDeleteContinuationStartIndex(actions: JSONArray?): Int? {
        if (actions == null) return null
        return backwardSmartDeleteContinuationStartIndex(
            (0 until actions.length()).mapNotNull { index ->
                val action = actions.optJSONObject(index) ?: return@mapNotNull null
                CustardDeleteContinuationAction(
                    type = action.optString("type"),
                    count = if (action.has("count")) action.optInt("count", 1)
                    else action.optString("value").toIntOrNull() ?: 1,
                    direction = action.optString("direction", "forward"),
                )
            },
        )
    }

    private fun canContinueDeleteLongPressIntoVariation(
        startActions: JSONArray,
        repeatActions: JSONArray,
        variationActions: JSONArray?,
    ): Boolean {
        if (backwardWordDeleteContinuationStartIndex(variationActions) == null) return false
        val centerActions = listOf(startActions, repeatActions)
        var foundDelete = false
        for (actions in centerActions) {
            for (index in 0 until actions.length()) {
                if (!positiveBackwardDelete(actions.optJSONObject(index))) return false
                foundDelete = true
            }
        }
        return foundDelete
    }

    private fun activeCustard(): JSONObject? {
        val id = activeCustomTab ?: return null
        val custards = state.optJSONArray("custards") ?: return null
        for (index in 0 until custards.length()) {
            val custard = custards.optJSONObject(index) ?: continue
            if (custard.optString("identifier") == id) return custard
        }
        return null
    }

    private fun compositionSnapshot() = CompositionSnapshot(
        composing = composing,
        rawRoman = rawRoman,
        mode = mode,
        layout = layout,
    )

    private fun restoreComposition(snapshot: CompositionSnapshot) {
        if (settings.optBoolean("enable_zenzai", true)) zenzaiRuntime.cancel()
        composing = snapshot.composing
        rawRoman = snapshot.rawRoman
        mode = snapshot.mode
        layout = snapshot.layout
        if (composing.isEmpty() && rawRoman.isEmpty()) clearComposition() else updateComposition()
    }

    private fun canRollbackCustardInputActions(vararg actionGroups: JSONArray): Boolean {
        val custard = activeCustard() ?: return false
        if (custard.optString("language", "undefined") != "ja_JP") return false
        var foundInput = false
        for (actions in actionGroups) {
            for (index in 0 until actions.length()) {
                val action = actions.optJSONObject(index) ?: return false
                if (action.optString("type", "input") != "input" || !action.has("text")) return false
                val text = action.optString("text")
                if (
                    text.isEmpty() ||
                    shouldDirectCommitJapaneseInput(text, JapaneseInputContext.CUSTARD_ACTION_SEQUENCE)
                ) return false
                foundInput = true
            }
        }
        return foundInput
    }

    private fun custardInput(value: String) {
        if (value.isEmpty()) return
        val custard = activeCustard()
        val language = custard?.optString("language", "undefined") ?: "undefined"
        val inputStyle = custard?.optString("input_style", "direct") ?: "direct"
        if (language == "en_US") {
            mode = "english"
            inputEnglishText(value)
            return
        }
        if (language != "ja_JP") {
            directCommit(value)
            return
        }
        if (
            shouldDirectCommitJapaneseInput(
                value,
                JapaneseInputContext.CUSTARD_ACTION_SEQUENCE,
            )
        ) {
            directCommit(value)
            return
        }
        mode = "japanese"
        if (inputStyle == "roman2kana") {
            layout = "qwerty"
            rawRoman += value.lowercase(Locale.ROOT)
            composing = romanToHiragana(rawRoman)
        } else {
            layout = "flick"
            composing += value
        }
        updateComposition()
    }

    private fun moveCursor(count: Int) {
        val keyCode = if (count < 0) KeyEvent.KEYCODE_DPAD_LEFT else KeyEvent.KEYCODE_DPAD_RIGHT
        repeat(abs(count).coerceAtMost(100)) {
            currentInputConnection?.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            currentInputConnection?.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
        }
        cursorBarView?.post { cursorBarView?.refresh() }
    }

    private fun replaceDefault() {
        if (composing.isNotEmpty()) {
            transformLastCharacter()
            return
        }
        val before = currentInputConnection?.getTextBeforeCursor(2, 0)?.toString().orEmpty()
        val last = before.takeLast(1)
        val replacement = kanaCharacterFormReplacement(last) ?: return
        currentInputConnection?.deleteSurroundingText(last.length, 0)
        currentInputConnection?.commitText(replacement, 1)
    }

    private fun replaceLastCharacters(table: JSONObject?) {
        if (table == null) return
        val before = if (composing.isNotEmpty()) composing
        else currentInputConnection?.getTextBeforeCursor(256, 0)?.toString().orEmpty()
        val replacements = table.keys().asSequence().associateWith(table::optString)
        val replacement = lastCharactersReplacementIn(before, replacements) ?: return
        if (composing.isNotEmpty()) {
            composing = replacement.applyTo(before)
            updateComposition()
        } else {
            currentInputConnection?.deleteSurroundingText(replacement.removedLength, 0)
            currentInputConnection?.commitText(replacement.replacement, 1)
        }
    }

    private fun actionTargets(action: JSONObject): List<String> {
        val values = action.optJSONArray("targets") ?: return defaultScanTargets
        return (0 until values.length()).map(values::optString).filter(String::isNotEmpty)
    }

    private fun smartDeleteDefault() {
        if (composing.isNotEmpty() || rawRoman.isNotEmpty()) {
            clearComposition()
            return
        }
        smartDelete(JSONObject().put("direction", "backward").put("targets", JSONArray(defaultScanTargets)))
    }

    private fun smartDelete(action: JSONObject) {
        val targets = actionTargets(action)
        val backward = action.optString("direction", "forward") == "backward"
        if (composing.isNotEmpty() || rawRoman.isNotEmpty()) {
            // The local composition cursor is at the trailing edge. Apply the
            // requested boundaries to direct kana input so a word-delete action
            // removes only the current token, not the complete composition.
            if (backward && rawRoman.isEmpty()) {
                val count = smartDeleteCount(composing, targets, backward = true)
                composing = composing.dropLast(count.coerceAtMost(composing.length))
                if (composing.isEmpty()) clearComposition() else updateComposition()
            } else if (backward) {
                // A roman buffer cannot be sliced safely by its converted kana
                // length, so match azooKey and clear that active composition.
                clearComposition()
            }
            return
        }
        if (backward) {
            val text = currentInputConnection?.getTextBeforeCursor(2000, 0)?.toString().orEmpty()
            currentInputConnection?.deleteSurroundingText(
                smartDeleteCount(text, targets, backward = true),
                0,
            )
            cursorBarView?.post { cursorBarView?.refresh() }
        } else {
            val text = currentInputConnection?.getTextAfterCursor(2000, 0)?.toString().orEmpty()
            currentInputConnection?.deleteSurroundingText(
                0,
                smartDeleteCount(text, targets, backward = false),
            )
            cursorBarView?.post { cursorBarView?.refresh() }
        }
    }

    private fun smartMoveCursor(action: JSONObject) {
        val targets = actionTargets(action)
        val backward = action.optString("direction", "forward") == "backward"
        val text = if (backward) {
            currentInputConnection?.getTextBeforeCursor(2000, 0)?.toString().orEmpty()
        } else {
            currentInputConnection?.getTextAfterCursor(2000, 0)?.toString().orEmpty()
        }
        val distance = if (backward) {
            val boundary = targets.mapNotNull { target ->
                val index = text.lastIndexOf(target)
                if (index < 0) null else index + target.length
            }.maxOrNull() ?: 0
            boundary - text.length
        } else {
            targets.mapNotNull { target ->
                val index = text.indexOf(target)
                if (index < 0) null else index
            }.minOrNull() ?: text.length
        }
        moveCursor(distance)
    }

    private fun selectCandidate(selection: JSONObject?) {
        if (candidates.isEmpty()) return
        selectedCandidate = when (selection?.optString("type")) {
            "last" -> candidates.lastIndex
            "offset" -> selectedCandidate + selection.optInt("value")
            "exact" -> selection.optInt("value")
            else -> 0
        }.coerceIn(0, candidates.lastIndex)
        currentInputConnection?.setComposingText(candidates[selectedCandidate], 1)
        renderCandidateValues()
    }

    private fun completeCharacterForm(forms: JSONArray?) {
        val source = displayReading()
        if (source.isEmpty()) return
        val form = forms?.optString(0).orEmpty()
        val converted = when (form) {
            "hiragana" -> katakanaToHiragana(source)
            "katakana" -> hiraganaToKatakana(source)
            "halfwidth_katakana" -> katakanaToHalfWidth(hiraganaToKatakana(source))
            "uppercase" -> source.uppercase(Locale.ROOT)
            "lowercase" -> source.lowercase(Locale.ROOT)
            else -> source
        }
        currentInputConnection?.commitText(converted, 1)
        composing = ""
        rawRoman = ""
        renderCandidates()
    }

    private fun moveTab(action: JSONObject) {
        if (action.optString("tab_type") == "custom") {
            commitComposition()
            activeCustomTab = action.optString("identifier")
            renderCandidates()
            renderKeyboard()
            return
        }
        when (action.optString("identifier")) {
            "user_japanese" -> setMode("japanese")
            "user_english" -> setMode("english")
            "flick_japanese" -> setForcedLayout("japanese", "flick")
            "flick_english" -> setForcedLayout("english", "flick")
            "qwerty_japanese" -> setForcedLayout("japanese", "qwerty")
            "qwerty_english" -> setForcedLayout("english", "qwerty")
            "flick_numbersymbols", "qwerty_numbers", "qwerty_symbols" -> setMode("symbols")
            "clipboard_history_tab" -> showClipboardHistory()
            "emoji_tab" -> showEmoji()
            "last_tab" -> setMode("japanese")
        }
    }

    private fun setForcedLayout(newMode: String, newLayout: String) {
        commitComposition()
        mode = newMode
        layout = newLayout
        activeCustomTab = null
        renderCandidates()
        renderKeyboard()
    }

    private fun launchApplication(action: JSONObject) {
        val scheme = action.optString("scheme_type")
        val target = action.optString("target")
        val intent = if (scheme == "azooKey") {
            packageManager.getLaunchIntentForPackage(packageName)
        } else {
            Intent(Intent.ACTION_VIEW, Uri.parse(if (target.contains("://")) target else "shortcuts://run-shortcut?name=${Uri.encode(target)}"))
        } ?: return
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { startActivity(intent) }
    }

    private fun paste() {
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        val value = clipboard.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString() ?: return
        directCommit(value)
    }

    private fun transformLastCharacter() {
        if (composing.isNotEmpty()) {
            val last = composing.last().toString()
            val transformed = kanaCharacterFormReplacement(last) ?: return
            composing = composing.dropLast(1) + transformed
            updateComposition()
            return
        }
        val connection = currentInputConnection ?: return
        val before = connection.getTextBeforeCursor(2, 0)?.toString().orEmpty()
        val last = before.takeLast(1)
        val transformed = kanaCharacterFormReplacement(last) ?: return
        connection.deleteSurroundingText(last.length, 0)
        connection.commitText(transformed, 1)
    }

    private fun displayReading(): String = when {
        mode == "english" -> composing
        layout == "qwerty" -> romanToHiragana(rawRoman)
        else -> composing
    }

    private fun feedback(view: View) {
        if (settings.optBoolean("enable_key_haptics", false)) {
            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
        }
        if (settings.optBoolean("sound_enable_setting", false)) {
            (getSystemService(AUDIO_SERVICE) as AudioManager).playSoundEffect(AudioManager.FX_KEYPRESS_STANDARD)
        }
    }

    private fun prepareZenzaiIfNeeded() {
        if (!settings.optBoolean("enable_zenzai", true)) return
        val effort = settings.optInt("zenzai_effort", 1)
        zenzaiRuntime.prepare(if (effort == 0) "xsmall" else "small")
    }

    private fun roundedDrawable(color: Int, radius: Float) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = radius
        setStroke(dp(1), Color.argb(32, 0, 0, 0))
    }

    private fun longPressDelay(explicitDuration: String? = null): Long {
        return longPressDelayMillis(
            explicitDuration,
            settings.optDouble("long_press_duration_ms", 400.0),
        )
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
        val customTarget: String? = null,
    )

    /** Reflect-style cursor bar used by azooKey's new cursor-bar setting. */
    private inner class CursorBarView : View(this@AzooKeyInputMethodService) {
        private val handler = Handler(Looper.getMainLooper())
        private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val symbolPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private var line = emptyList<String>()
        private var displayLeftIndex = 0
        private var displayRightIndex = 0
        private var itemCount = 0
        private var itemWidth = dp(20).toFloat()
        private var downX = 0f
        private var downY = 0f
        private var lastX = 0f
        private var last2X = 0f
        private var last3X = 0f
        private var swipeCount = 0.0
        private var moving = false
        private var arrowOffset = 0
        private var arrowLongPressed = false
        private var arrowDownAt = 0L
        private var autoDismiss: Runnable? = null
        private val arrowRepeat = object : Runnable {
            override fun run() {
                if (!arrowLongPressed) return
                move(arrowOffset)
                handler.postDelayed(this, 100)
            }
        }
        private val arrowLongPress = Runnable {
            if (arrowOffset == 0) return@Runnable
            arrowLongPressed = true
            move(arrowOffset)
            handler.post(arrowRepeat)
            feedback(this)
        }

        init {
            isClickable = true
            textPaint.textAlign = Paint.Align.CENTER
            textPaint.typeface = Typeface.DEFAULT_BOLD
            symbolPaint.textAlign = Paint.Align.CENTER
            symbolPaint.typeface = Typeface.DEFAULT_BOLD
            setWillNotDraw(false)
        }

        fun refresh() {
            val before = currentInputConnection?.getTextBeforeCursor(2000, 0)?.toString().orEmpty()
            val after = currentInputConnection?.getTextAfterCursor(2000, 0)?.toString().orEmpty()
            val left = before.substringAfterLast('\n')
            line = (left + after).map { it.toString() } + listOf("⏎")
            val half = itemCount / 2
            displayLeftIndex = line.size - half
            displayRightIndex = displayLeftIndex + itemCount
            invalidate()
        }

        fun scheduleAutoDismiss() {
            autoDismiss?.let(handler::removeCallbacks)
            val task = Runnable {
                if (cursorBarVisible) {
                    cursorBarVisible = false
                    cursorBarView = null
                    renderCandidates()
                }
            }
            autoDismiss = task
            handler.postDelayed(task, 10_000)
        }

        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            super.onSizeChanged(w, h, oldw, oldh)
            val size = settings.optDouble("result_view_font_size", 16.0).toFloat().coerceAtLeast(12f)
            itemWidth = size * 1.3f * resources.displayMetrics.scaledDensity
            itemCount = ((w / itemWidth).toInt() shr 1) shl 1
            refresh()
        }

        private fun move(count: Int) {
            val center = displayLeftIndex + itemCount / 2
            if (center + count < -1 || line.size < center + count) return
            displayLeftIndex += count
            displayRightIndex += count
            moveCursor(count)
            invalidate()
        }

        private fun tap(x: Float) {
            if (width <= 0 || itemWidth <= 0) return
            val offset = ((x - width / 2f) / itemWidth).roundToInt()
            move(offset)
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val center = width / 2f
            val radius = width / 2f
            val gradient = RadialGradient(center, height / 2f, radius, palette.key, palette.background, Shader.TileMode.CLAMP)
            canvas.drawPaint(Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = gradient })
            val size = settings.optDouble("result_view_font_size", 16.0).toFloat().coerceAtLeast(12f)
            textPaint.textSize = size * resources.displayMetrics.scaledDensity
            textPaint.color = Color.argb(105, Color.red(palette.text), Color.green(palette.text), Color.blue(palette.text))
            val start = displayLeftIndex - 4
            for (index in start until displayRightIndex + 4) {
                val value = line.getOrNull(index) ?: ""
                if (value.isEmpty()) continue
                val x = center + (index - (displayLeftIndex + itemCount / 2)) * itemWidth
                canvas.drawText(value, x, height / 2f - (textPaint.ascent() + textPaint.descent()) / 2f, textPaint)
            }
            symbolPaint.textSize = dp(18).toFloat()
            symbolPaint.color = palette.text
            canvas.drawText("‹‹", dp(22).toFloat(), height / 2f - (symbolPaint.ascent() + symbolPaint.descent()) / 2f, symbolPaint)
            canvas.drawText("››", width - dp(22).toFloat(), height / 2f - (symbolPaint.ascent() + symbolPaint.descent()) / 2f, symbolPaint)
            symbolPaint.textSize = (size + 4) * resources.displayMetrics.scaledDensity
            canvas.drawText("│", center, height / 2f - (symbolPaint.ascent() + symbolPaint.descent()) / 2f, symbolPaint)
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.x
                    downY = event.y
                    lastX = downX
                    last2X = downX
                    last3X = downX
                    swipeCount = 0.0
                    moving = false
                    arrowLongPressed = false
                    arrowDownAt = System.currentTimeMillis()
                    arrowOffset = when {
                        event.x < dp(48) -> -1
                        event.x > width - dp(48) -> 1
                        else -> 0
                    }
                    if (arrowOffset != 0) handler.postDelayed(arrowLongPress, longPressDelay())
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val distance = kotlin.math.hypot(event.x - downX, event.y - downY)
                    if (distance > dp(20)) {
                        handler.removeCallbacks(arrowLongPress)
                        if (arrowOffset == 0) moving = true
                    }
                    if (arrowOffset == 0 && moving) {
                        var direction = 0
                        if (event.x - lastX > 0) direction -= 1 else direction += 1
                        if (lastX - last2X > 0) direction -= 1 else direction += 1
                        if (last2X - last3X > 0) direction -= 1 else direction += 1
                        if (direction > 0 && event.x < last3X) swipeCount += (direction / 3.0) * (last3X - event.x) / 3.0
                        else if (direction < 0 && event.x > last3X) swipeCount -= (direction / 3.0) * (last3X - event.x) / 3.0
                        while (swipeCount >= 15) { move(1); swipeCount -= 15 }
                        while (swipeCount <= -15) { move(-1); swipeCount += 15 }
                    }
                    last3X = last2X
                    last2X = lastX
                    lastX = event.x
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    handler.removeCallbacks(arrowLongPress)
                    handler.removeCallbacks(arrowRepeat)
                    val elapsed = System.currentTimeMillis() - arrowDownAt
                    if (arrowOffset != 0) {
                        if (!arrowLongPressed && elapsed < longPressDelay() && kotlin.math.hypot(event.x - downX, event.y - downY) <= dp(20)) move(arrowOffset)
                    } else if (!moving) {
                        tap(downX)
                    }
                    arrowOffset = 0
                    return true
                }
                MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(arrowLongPress)
                    handler.removeCallbacks(arrowRepeat)
                    arrowOffset = 0
                    return true
                }
            }
            return true
        }
    }

    private data class FlickGuide(
        val popup: PopupWindow,
        val centerCell: TextView,
        val directionCells: Map<String, TextView>,
    )

    private data class CompositionSnapshot(
        val composing: String,
        val rawRoman: String,
        val mode: String,
        val layout: String,
    )

    data class KeyboardPalette(
        val background: Int,
        val key: Int,
        val special: Int,
        val text: Int,
        val accent: Int,
        val backgroundImage: String? = null,
        val backgroundImageRevision: Long? = null,
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
        private const val KEYNAKO_HOTFIX_STORAGE_KEY =
            "keynako_hotfix_dictionary_storage"
        private const val KEYNAKO_HOTFIX_LATEST_SHA_KEY =
            "keynako_hotfix_dictionary_storage_latest_sha"
        private const val LEGACY_AZOOKEY_HOTFIX_STORAGE_KEY =
            "azooKey_hotfix_dictionary_storage"
        private const val LEGACY_AZOOKEY_HOTFIX_LATEST_TAG_KEY =
            "azooKey_hotfix_dictionary_storage_latest_tag"
        private const val IME_LOG_TAG = "KeynakoIME"
        private const val ACTIVE_CUSTOM_TAB_KEY = "keynako_active_custom_tab"
        @Volatile
        var activeInstance: AzooKeyInputMethodService? = null

        private const val ONE_HANDED_MODE_KEY = "keynako_one_handed_mode"
        private const val PREDICTION_INSERT_INDEX = 2
        private const val PREDICTION_LIMIT = 32

        internal fun withOpacity(color: Int, opacity: Double): Int {
            val alpha = (Color.alpha(color) * opacity).toInt().coerceIn(0, 255)
            return Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
        }
        private val systemDictionary = mapOf(
            "あい" to listOf("愛", "藍", "相"),
            "あう" to listOf("会う", "合う", "遭う"),
            "あさ" to listOf("朝", "麻"),
            "あした" to listOf("明日"),
            "ありがとう" to listOf("ありがとう", "有難う"),
            "いま" to listOf("今", "居間"),
            "おねがい" to listOf("お願い"),
            "かめんらいだー" to listOf("仮面ライダー"),
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
            "これ" to listOf("これ", "此れ"),
            "それ" to listOf("それ", "其れ"),
            "ここ" to listOf("ここ", "此処"),
            "こと" to listOf("こと", "事"),
            "もの" to listOf("もの", "物"),
            "ひと" to listOf("人"),
            "ともだち" to listOf("友達"),
            "かぞく" to listOf("家族"),
            "せんせい" to listOf("先生"),
            "がくせい" to listOf("学生"),
            "かいしゃ" to listOf("会社"),
            "しごと" to listOf("仕事"),
            "きのう" to listOf("昨日"),
            "ひる" to listOf("昼"),
            "よる" to listOf("夜"),
            "てんき" to listOf("天気"),
            "あめ" to listOf("雨", "飴"),
            "はれ" to listOf("晴れ"),
            "ゆき" to listOf("雪", "行き"),
            "みず" to listOf("水"),
            "たべもの" to listOf("食べ物"),
            "のみもの" to listOf("飲み物"),
            "ごはん" to listOf("ご飯"),
            "おちゃ" to listOf("お茶"),
            "でんしゃ" to listOf("電車"),
            "えき" to listOf("駅"),
            "くるま" to listOf("車"),
            "びょういん" to listOf("病院"),
            "だいがく" to listOf("大学"),
            "がっこう" to listOf("学校"),
            "ほん" to listOf("本", "ほん"),
            "なまえ" to listOf("名前"),
            "めーる" to listOf("メール"),
            "ほうほう" to listOf("方法"),
            "もんだい" to listOf("問題"),
            "かいけつ" to listOf("解決"),
            "せいこう" to listOf("成功"),
            "しっぱい" to listOf("失敗"),
            "かくにん" to listOf("確認"),
            "せつめい" to listOf("説明"),
            "へんこう" to listOf("変更"),
            "ほぞん" to listOf("保存"),
            "けんさく" to listOf("検索"),
            "けっか" to listOf("結果"),
            "ひつよう" to listOf("必要"),
            "たいせつ" to listOf("大切"),
            "べんり" to listOf("便利"),
            "かんたん" to listOf("簡単"),
            "むずかしい" to listOf("難しい"),
            "おおきい" to listOf("大きい"),
            "ちいさい" to listOf("小さい"),
            "はやい" to listOf("早い", "速い"),
            "おそい" to listOf("遅い"),
            "いい" to listOf("いい", "良い"),
            "わるい" to listOf("悪い"),
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
    }
}

/** A decorative image must never contribute its bitmap's intrinsic size to the IME. */
private class KeyboardBackgroundImageView(context: Context) : ImageView(context) {
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(
            decorativeImageMeasuredDimension(
                isExact = View.MeasureSpec.getMode(widthMeasureSpec) == View.MeasureSpec.EXACTLY,
                exactSize = View.MeasureSpec.getSize(widthMeasureSpec),
            ),
            decorativeImageMeasuredDimension(
                isExact = View.MeasureSpec.getMode(heightMeasureSpec) == View.MeasureSpec.EXACTLY,
                exactSize = View.MeasureSpec.getSize(heightMeasureSpec),
            ),
        )
    }
}

internal fun decorativeImageMeasuredDimension(isExact: Boolean, exactSize: Int): Int =
    if (isExact) exactSize else 0

internal fun shouldReloadKeyboardBackground(
    signature: String,
    loadedSignature: String?,
    hasDrawable: Boolean,
): Boolean = signature != loadedSignature || !hasDrawable
