package com.retrolan.retrolan_controller

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * RetroLAN Controller — Android host.
 * Exposes a 'pickFile' method to Flutter (via MethodChannel) so the "Send ROM to TV"
 * feature can select a local file on the phone and return its name + bytes. This is the
 * user's own file; it is only ever sent to the TV over the LAN and played there.
 */
class MainActivity : FlutterActivity() {
    private val channel = "retrolan/filepicker"
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                if (call.method == "pickFile") {
                    pendingResult = result
                    openFilePicker()
                } else {
                    result.notImplemented()
                }
            }
    }

    /** Launch the system document picker for a single file (any type). */
    private fun openFilePicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        try {
            startActivityForResult(intent, REQ_PICK)
        } catch (e: Exception) {
            pendingResult?.error("picker", "No file picker available: ${e.message}", null)
            pendingResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_PICK) {
            val uri: Uri? = data?.data
            if (resultCode == Activity.RESULT_OK && uri != null) {
                readFile(uri)
            } else {
                // user cancelled
                pendingResult?.success(null)
                pendingResult = null
            }
        }
    }

    /** Read the picked file's display name + bytes and hand back to Flutter. */
    private fun readFile(uri: Uri) {
        var name = "game"
        try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) cursor.getString(idx)?.let { name = it }
                }
            }
        } catch (_: Exception) {}
        try {
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: ByteArray(0)
            val map = HashMap<String, Any>() // ByteArray -> List<Int> for easy Dart transfer
            map["name"] = name
            map["bytes"] = bytes.toList()
            pendingResult?.success(map)
        } catch (e: Exception) {
            pendingResult?.error("read", "Could not read file: ${e.message}", null)
        }
        pendingResult = null
        Log.i("RetroLAN-Upload", "picked $name (${uri} sized)")
    }

    companion object {
        private const val REQ_PICK = 9901
    }
}
