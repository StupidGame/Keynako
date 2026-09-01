package io.github.StupidGame.azookey_flutter

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.provider.ContactsContract
import android.provider.Settings
import android.system.Os
import android.view.inputmethod.InputMethodManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingContactResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "loadState" -> result.success(sharedPreferences().getString(STATE_KEY, null))
                "saveState" -> {
                    val state = call.argument<String>("state")
                    if (state == null) {
                        result.error("invalid_state", "state must be a JSON string", null)
                    } else {
                        sharedPreferences().edit().putString(STATE_KEY, state).apply()
                        AzooKeyInputMethodService.activeInstance?.refreshFromApp()
                        result.success(null)
                    }
                }
                "keyboardStatus" -> result.success(keyboardStatus())
                "openKeyboardSettings" -> {
                    startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
                    result.success(null)
                }
                "shareText" -> {
                    val share = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_SUBJECT, call.argument<String>("subject") ?: "Keynako")
                        putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "")
                    }
                    startActivity(Intent.createChooser(share, "共有"))
                    result.success(null)
                }
                "importContacts" -> importContacts(result)
                "saveKeyboardBackgroundImage" -> {
                    val themeId = call.argument<String>("themeId").orEmpty()
                    val bytes = call.argument<ByteArray>("bytes")
                    if (themeId.isBlank() || bytes == null || bytes.isEmpty()) {
                        result.error("invalid_image", "themeId and image bytes are required", null)
                    } else if (bytes.size > MAX_BACKGROUND_IMAGE_BYTES) {
                        result.error("image_too_large", "background image exceeds 8 MB", null)
                    } else {
                        runCatching { saveKeyboardBackgroundImage(themeId, bytes) }
                            .onSuccess(result::success)
                            .onFailure {
                                result.error("image_save_failed", it.localizedMessage, null)
                            }
                    }
                }
                "deleteKeyboardBackgroundImage" -> {
                    val path = call.argument<String>("path")
                    if (path != null) deleteKeyboardBackgroundImage(path)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun sharedPreferences() = getSharedPreferences(PREFERENCES_NAME, MODE_PRIVATE)

    private fun keyboardStatus(): Map<String, Any> {
        val manager = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
        val enabled = manager.enabledInputMethodList.any { info ->
            info.packageName == packageName &&
                info.serviceName == AzooKeyInputMethodService::class.java.name
        }
        val selected = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.DEFAULT_INPUT_METHOD,
        )?.contains(packageName) == true
        return mapOf(
            "enabled" to enabled,
            "fullAccess" to selected,
            "platform" to "android",
        )
    }

    private fun importContacts(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CONTACTS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(readContacts())
            return
        }
        if (pendingContactResult != null) {
            result.error("request_in_progress", "A contact request is already active", null)
            return
        }
        pendingContactResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.READ_CONTACTS),
            CONTACTS_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CONTACTS_PERMISSION_REQUEST) return

        val result = pendingContactResult
        pendingContactResult = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            result?.success(readContacts())
        } else {
            result?.error("permission_denied", "Contacts permission was denied", null)
        }
    }

    private fun readContacts(): List<Map<String, String>> {
        val contacts = linkedMapOf<String, String>()
        val projection = arrayOf(
            ContactsContract.Contacts.DISPLAY_NAME_PRIMARY,
            ContactsContract.CommonDataKinds.StructuredName.PHONETIC_FAMILY_NAME,
            ContactsContract.CommonDataKinds.StructuredName.PHONETIC_GIVEN_NAME,
        )
        val selection = "${ContactsContract.Data.MIMETYPE} = ?"
        val arguments = arrayOf(ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE)
        contentResolver.query(
            ContactsContract.Data.CONTENT_URI,
            projection,
            selection,
            arguments,
            null,
        )?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(ContactsContract.Contacts.DISPLAY_NAME_PRIMARY)
            val familyIndex = cursor.getColumnIndex(
                ContactsContract.CommonDataKinds.StructuredName.PHONETIC_FAMILY_NAME,
            )
            val givenIndex = cursor.getColumnIndex(
                ContactsContract.CommonDataKinds.StructuredName.PHONETIC_GIVEN_NAME,
            )
            while (cursor.moveToNext()) {
                val name = cursor.getString(nameIndex)?.trim().orEmpty()
                if (name.isEmpty()) continue
                val ruby = buildString {
                    if (familyIndex >= 0) append(cursor.getString(familyIndex).orEmpty())
                    if (givenIndex >= 0) append(cursor.getString(givenIndex).orEmpty())
                }.trim().ifEmpty { name }
                contacts[name] = ruby
            }
        }
        return contacts.map { (word, ruby) -> mapOf("word" to word, "ruby" to ruby) }
    }

    private fun saveKeyboardBackgroundImage(themeId: String, bytes: ByteArray): String {
        val directory = backgroundImageDirectory()
        check(directory.exists() || directory.mkdirs()) {
            "Could not create the theme background directory"
        }
        val safeId = themeId
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .take(80)
            .ifBlank { "theme" }
        val target = File(directory, "$safeId.image")
        val temporary = File.createTempFile(".$safeId-", ".tmp", directory)
        try {
            val imageBounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, imageBounds)
            check(imageBounds.outWidth > 0 && imageBounds.outHeight > 0) {
                "Could not decode the background image"
            }
            // Keep the source aspect ratio. The IME crops it against its actual
            // bounds, which vary with device width, height scale, and one-handed mode.
            temporary.writeBytes(bytes)
            // The IME can read this file while the settings app is open. A POSIX
            // rename replaces it atomically, so the decoder never sees a partial image.
            Os.rename(temporary.absolutePath, target.absolutePath)
        } finally {
            temporary.delete()
        }
        return target.absolutePath
    }

    private fun deleteKeyboardBackgroundImage(path: String) {
        val directory = backgroundImageDirectory().canonicalFile
        val target = File(path).canonicalFile
        if (target.parentFile == directory) target.delete()
    }

    private fun backgroundImageDirectory() = File(filesDir, "theme_backgrounds")

    companion object {
        const val CHANNEL = "net.azookey/platform"
        const val PREFERENCES_NAME = "azookey_flutter"
        const val STATE_KEY = "azookey_flutter_state"
        private const val CONTACTS_PERMISSION_REQUEST = 4101
        private const val MAX_BACKGROUND_IMAGE_BYTES = 8 * 1024 * 1024
    }
}
