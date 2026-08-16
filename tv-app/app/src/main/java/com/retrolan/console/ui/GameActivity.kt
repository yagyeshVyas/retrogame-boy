package com.retrolan.console.ui

import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import android.view.KeyEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.widget.FrameLayout
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.retrolan.console.R
import com.retrolan.console.core.LibRetro
import com.retrolan.console.network.RetroServer
import java.io.File
import java.io.FileOutputStream

/**
 * Game screen. Holds a SurfaceView sized to the core's aspect ratio (4:3 for NES —
 * never stretched to 16:9), runs the emulator, maps both a physical gamepad *and*
 * LAN controller input into the core.
 *
 * RetroLAN-original (GPLv3 under /tv-app).
 */
class GameActivity : AppCompatActivity() {

    private lateinit var holder: SurfaceHolder

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val sv = object : SurfaceView(this) {
            override fun onMeasure(wSpec: Int, hSpec: Int) {
                // 4:3 NES aspect, uncropped
                val w = MeasureSpec.getSize(wSpec)
                val h = (w * 3 / 4).coerceAtMost(MeasureSpec.getSize(hSpec))
                setMeasuredDimension(w, h)
            }
        }
        holder = sv.holder
        val layout = FrameLayout(this)
        layout.addView(sv, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        setContentView(layout)

        val romName = intent.getStringExtra("romName") ?: "game"
        val romUri = intent.getStringExtra("romUri")

        // v1 loads a local file path; SAF full content streaming is a follow-up.
        val local = File(cacheDir, "current.$romName")
        holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(h: SurfaceHolder) {
                copyToCache(romUri, local)
                val system = LibRetro.loadGameByPath(local.absolutePath)
                if (system != null) {
                    LibRetro.start()
                    Toast.makeText(this@GameActivity, "Playing: $system (local file)", Toast.LENGTH_LONG).show()
                } else {
                    Toast.makeText(this@GameActivity, "No core for that ROM", Toast.LENGTH_LONG).show()
                }
            }
            override fun surfaceChanged(h: SurfaceHolder, f: Int, w: Int, hh: Int) {}
            override fun surfaceDestroyed(h: SurfaceHolder) { LibRetro.stop() }
        })

        RetroServer.onControllerCount = { n -> runOnUiThread {
            Toast.makeText(this, "$n controller(s)", Toast.LENGTH_SHORT).show()
        } }
    }

    private fun copyToCache(uriString: String?, dest: File) {
        if (uriString == null) return
        val uri = android.net.Uri.parse(uriString)
        try {
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(dest).use { out -> input.copyTo(out) }
            }
        } catch (e: Exception) { e.printStackTrace() }
    }

    // Physical gamepad -> core (in addition to LAN controllers).
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val id = when (event.keyCode) {
            KeyEvent.KEYCODE_DPAD_UP -> LibRetro.BTN_UP
            KeyEvent.KEYCODE_DPAD_DOWN -> LibRetro.BTN_DOWN
            KeyEvent.KEYCODE_DPAD_LEFT -> LibRetro.BTN_LEFT
            KeyEvent.KEYCODE_DPAD_RIGHT -> LibRetro.BTN_RIGHT
            KeyEvent.KEYCODE_BUTTON_A, KeyEvent.KEYCODE_A -> LibRetro.BTN_A
            KeyEvent.KEYCODE_BUTTON_B, KeyEvent.KEYCODE_B -> LibRetro.BTN_B
            KeyEvent.KEYCODE_BUTTON_X, KeyEvent.KEYCODE_X -> LibRetro.BTN_X
            KeyEvent.KEYCODE_BUTTON_Y, KeyEvent.KEYCODE_Y -> LibRetro.BTN_Y
            KeyEvent.KEYCODE_BUTTON_START, KeyEvent.KEYCODE_ENTER -> LibRetro.BTN_START
            KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.KEYCODE_BACK -> LibRetro.BTN_SELECT
            else -> -1
        }
        if (id == -1) return super.dispatchKeyEvent(event)
        val down = event.action != KeyEvent.ACTION_UP
        // map physical pad to player 1
        if (LibRetro.buttonToLibretro(protocolFor(id)) != null) {
            setButtonByLibretro(0, id, down)
        }
        return true
    }

    private fun protocolFor(id: Int): String = when (id) {
        LibRetro.BTN_UP -> "dpad_up"; LibRetro.BTN_DOWN -> "dpad_down"
        LibRetro.BTN_LEFT -> "dpad_left"; LibRetro.BTN_RIGHT -> "dpad_right"
        LibRetro.BTN_A -> "a"; LibRetro.BTN_B -> "b"; LibRetro.BTN_X -> "x"; LibRetro.BTN_Y -> "y"
        LibRetro.BTN_START -> "start"; LibRetro.BTN_SELECT -> "select"
        LibRetro.BTN_L -> "l"; LibRetro.BTN_R -> "r"; else -> ""
    }

    // The C bridge's nativeSetButton is bound via LibRetro.press; here we call the
    // libretro-id variant directly through a small native helper used for the pad.
    private fun setButtonByLibretro(player: Int, id: Int, down: Boolean) {
        LibRetro.press(protocolFor(id), down, player + 1)
    }

    override fun onPause() {
        LibRetro.stop()
        super.onPause()
    }
    override fun onResume() {
        super.onResume()
        LibRetro.start()
    }
}
