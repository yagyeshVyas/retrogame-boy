package com.retrolan.console.core

import android.util.Log
import java.io.File
import kotlin.concurrent.thread

/**
 * JNI bridge to a dlopen'd libretro core (e.g. fceumm for NES).
 *
 * This class is RetroLAN-original. It wraps the thin native bridge in
 * [retro_core_jni.c]; the GPL libretro core itself is loaded at runtime and is
 * NOT compiled into this code (see docs/LICENSING.md).
 */
object LibRetro {
    private const val TAG = "LibRetro"

    /** libretro joypad ids — mirror the C header. */
    const val BTN_B = 0; const val BTN_Y = 1; const val BTN_SELECT = 2
    const val BTN_START = 3; const val BTN_UP = 4; const val BTN_DOWN = 5
    const val BTN_LEFT = 6; const val BTN_RIGHT = 7; const val BTN_A = 8
    const val BTN_X = 9; const val BTN_L = 10; const val BTN_R = 11

    init { System.loadLibrary("retro_bridge") }

    // Native declarations (implemented in retro_core_jni.c)
    private external fun nativeLoadCore(path: String): Boolean
    private external fun nativeRunFrame()
    private external fun nativeSetButton(player: Int, libretroId: Int, down: Boolean)
    private external fun nativeLoadGame(romPath: String, coreName: String): Boolean

    @Volatile var running = false
        private set

    /** Where a core .so named libretro_<core>.so lives (set to jniLibs/<abi>). */
    @Volatile var coreLibraryDir: File? = null
    @Volatile var systemDir: File? = null

    private var coreName: String? = null
    private var currentSystem: CoreDef? = null
    private var emuThread: Thread? = null

    /** Load a core by short name ("fceumm" -> libretro_fceumm.so in coreLibraryDir). */
    fun loadCore(name: String): Boolean {
        val dir = coreLibraryDir ?: return false
        val lib = File(dir, "libretro_$name.so")
        if (!lib.exists()) { Log.e(TAG, "core ${lib.absolutePath} not found"); return false }
        val ok = nativeLoadCore(lib.absolutePath)
        if (ok) { coreName = name; currentSystem = null }
        return ok
    }

    /**
     * Load a ROM file and the correct core for it, chosen from the extension via [Cores].
     * This is the one-call path that makes the whole supported-systems catalog playable.
     *
     * @return the friendly system name on success, or null on failure.
     */
    fun loadGameByPath(romPath: String): String? {
        val ext = romPath.substringAfterLast('.', "").lowercase()
        val def = Cores.resolve(ext) ?: run {
            Log.e(TAG, "no core for extension '.$ext' (supported: ${Cores.allExtensions})")
            return null
        }
        val dir = coreLibraryDir ?: return null
        val lib = File(dir, "libretro_${def.core}.so")
        if (!lib.exists()) {
            Log.e(TAG, "core '${def.core}' (${def.system}) not found at ${lib.absolutePath}")
            return null
        }
        val ok = nativeLoadCore(lib.absolutePath)
        if (!ok) return null
        coreName = def.core
        currentSystem = def
        val loaded = nativeLoadGame(romPath, def.core)
        if (!loaded) { Log.e(TAG, "load_game failed for $romPath with ${def.core}"); return null }
        Log.i(TAG, "playing ${def.system} on ${def.core}: $romPath")
        return def.system
    }

    /** A ROM's full path (override in tests / no-content builds). */
    fun loadGame(romPath: String): Boolean {
        val cn = coreName ?: return false
        return nativeLoadGame(romPath, cn)
    }

    /** Feed a protocol button transition into the core's joypad state. */
    fun press(protocolButton: String, down: Boolean, player: Int) {
        val id = buttonToLibretro(protocolButton) ?: return
        nativeSetButton(player - 1, id, down) // protocol is 1-based player
    }

    /** Start the emulation run loop on a dedicated thread (60 fps target). */
    fun start() {
        if (running) return
        running = true
        emuThread = thread(name = "retro-run") {
            val frameMs = 16L // ~60fps
            while (running) {
                val t0 = System.nanoTime()
                nativeRunFrame()
                val elapsed = (System.nanoTime() - t0) / 1_000_000
                val sleep = (frameMs - elapsed).coerceAtLeast(1)
                try { Thread.sleep(sleep) } catch (_: InterruptedException) { break }
            }
        }
    }

    fun stop() {
        running = false
        emuThread?.join(2000)
        emuThread = null
    }

    /** Map a protocol button name to a libretro joypad id. */
    fun buttonToLibretro(name: String): Int? = when (name) {
        "a" -> BTN_A; "b" -> BTN_B; "x" -> BTN_X; "y" -> BTN_Y
        "start" -> BTN_START; "select" -> BTN_SELECT
        "l" -> BTN_L; "r" -> BTN_R
        "dpad_up" -> BTN_UP; "dpad_down" -> BTN_DOWN
        "dpad_left" -> BTN_LEFT; "dpad_right" -> BTN_RIGHT
        else -> null
    }
}
