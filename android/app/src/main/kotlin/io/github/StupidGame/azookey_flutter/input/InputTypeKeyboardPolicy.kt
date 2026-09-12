package io.github.StupidGame.azookey_flutter.input

internal enum class RequestedKeyboardMode {
    JAPANESE,
    ENGLISH,
    NUMBER,
    PHONE,
    DATE_TIME,
}

/** Chooses the initial keyboard from Android's EditorInfo input contract. */
internal fun requestedKeyboardMode(
    inputType: Int,
    imeOptions: Int = 0,
    hintLocaleTags: List<String> = emptyList(),
): RequestedKeyboardMode {
    return when (inputType and TYPE_MASK_CLASS) {
        TYPE_CLASS_NUMBER -> RequestedKeyboardMode.NUMBER
        TYPE_CLASS_PHONE -> RequestedKeyboardMode.PHONE
        TYPE_CLASS_DATETIME -> RequestedKeyboardMode.DATE_TIME
        TYPE_CLASS_TEXT -> {
            val variation = inputType and TYPE_MASK_VARIATION
            if (
                variation in englishTextVariations ||
                imeOptions and IME_FLAG_FORCE_ASCII != 0 ||
                prefersEnglish(hintLocaleTags)
            ) {
                RequestedKeyboardMode.ENGLISH
            } else {
                RequestedKeyboardMode.JAPANESE
            }
        }
        else -> RequestedKeyboardMode.JAPANESE
    }
}

/** Password fields must not expose their contents in the candidate row. */
internal fun isSensitiveInputType(inputType: Int): Boolean {
    if (inputType and TYPE_MASK_CLASS != TYPE_CLASS_TEXT) return false
    return inputType and TYPE_MASK_VARIATION in passwordTextVariations
}

private fun prefersEnglish(localeTags: List<String>): Boolean {
    val primaryLanguage = localeTags.firstOrNull()
        ?.substringBefore('-')
        ?.substringBefore('_')
        ?.lowercase()
    return primaryLanguage == "en"
}

// Kept independent from android.jar so this policy remains a plain JVM unit.
private const val TYPE_MASK_CLASS = 0x0000000f
private const val TYPE_MASK_VARIATION = 0x00000ff0
private const val TYPE_CLASS_TEXT = 0x00000001
private const val TYPE_CLASS_NUMBER = 0x00000002
private const val TYPE_CLASS_PHONE = 0x00000003
private const val TYPE_CLASS_DATETIME = 0x00000004
private const val IME_FLAG_FORCE_ASCII = Int.MIN_VALUE

private val englishTextVariations = setOf(
    0x00000010, // URI
    0x00000020, // email address
    0x00000080, // password
    0x00000090, // visible password
    0x000000d0, // web email address
    0x000000e0, // web password
)

private val passwordTextVariations = setOf(
    0x00000080,
    0x00000090,
    0x000000e0,
)
