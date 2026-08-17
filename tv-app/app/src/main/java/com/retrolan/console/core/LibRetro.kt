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
    const val BTN_L2 = 12; const val BTN_R2 = 13

    init { System.loadLibrary("retro_bridge") }

    // Native declarations (implemented in retro_core_jni.c)
    private external fun nativeLoadCore(path: String): Boolean
    private external fun nativeRunFrame()
    private external fun nativeSetButton(player: Int, libretroId: Int, down: Boolean)
    private external fun nativeLoadGame(romPath: String, coreName: String): Boolean
    private external fun nativeCopyFrame(out: ByteArray): Int
    private external fun nativeFrameWidth(): Int
    private external fun nativeFrameHeight(): Int
    private external fun nativeFramePitch(): Int
    private external fun nativeFrameFormat(): Int
    private external fun nativeDrainAudio(out: ByteArray): Int
    private external fun nativeAudioRate(): Int
    private external fun nativeClearButtons()

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
     * Handles `.zip` containers by extracting the inner ROM into the cache first (the user's
     * own file, opened on this device — never fetched over the network).
     *
     * @return the friendly system name on success, or null on failure.
     */
    fun loadGameByPath(romPath: String): String? {
        var path = romPath
        var ext = path.substringAfterLast('.', "").lowercase()

        // .zip (or 7z-like) container: extract the single inner ROM to cache and load that.
        if (ext == Cores.ZIP_EXT) {
            val inner = extractRomFromZip(path, cacheDir) ?: run {
                Log.e(TAG, "no ROM found inside $romPath")
                return null
            }
            path = inner
            ext = path.substringAfterLast('.', "").lowercase()
        }

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
        // Fresh game: release any buttons left held from a previous session/game —
        // otherwise a stuck key (e.g. left) carries into the new game.
        nativeClearButtons()
        coreName = def.core
        currentSystem = def
        val loaded = nativeLoadGame(path, def.core)
        if (!loaded) { Log.e(TAG, "load_game failed for $path with ${def.core}"); return null }
        Log.i(TAG, "playing ${def.system} on ${def.core}: $path")
        return def.system
    }

    /** Cache dir the app writes extracted zipped ROMs to (set from GameActivity). */
    @Volatile var cacheDir: java.io.File? = null

    /** Extract the first supported ROM from a .zip into the cache; returns the inner path. */
    private fun extractRomFromZip(zipPath: String, cache: java.io.File?): String? {
        val dir = cache ?: return null
        dir.mkdirs()
        try {
            java.util.zip.ZipFile(zipPath).use { zip ->
                val entries = zip.entries()
                while (entries.hasMoreElements()) {
                    val entry = entries.nextElement()
                    if (entry.isDirectory) continue
                    val name = entry.name.substringAfterLast('/')
                    val innerExt = name.substringAfterLast('.', "").lowercase()
                    if (Cores.resolve(innerExt) == null) continue
                    val out = File(dir, "extracted_${System.currentTimeMillis()}.$innerExt")
                    out.outputStream().use { os -> zip.getInputStream(entry).copyTo(os) }
                    return out.absolutePath
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "extractRomFromZip failed: ${e.message}")
        }
        return null
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

    /** Release every held button (call on disconnect / fresh game load). */
    fun clearButtons() { nativeClearButtons() }

    /** Surface the rendered game frames are drawn to (set by GameActivity). */
    @Volatile var surfaceHolder: android.view.SurfaceHolder? = null

    /** Start the emulation run loop on a dedicated thread (~60 fps target). */
    fun start() {
        if (running) return
        running = true
        // ---- Audio thread: owns the AudioTrack; emulation thread only queues chunks,
        //      so a slow/full audio device can never stall video rendering. ----
        // Small buffer pool: NO per-frame allocations (GC pauses = video jank on
        // 32-bit TVs). Chunks are recycled after playback.
        val audioQueue = java.util.concurrent.LinkedBlockingQueue<ByteArray>(16)
        val audioPool = java.util.concurrent.ConcurrentLinkedQueue<ByteArray>()
        val audioThread = thread(name = "retro-audio") {
            var at: android.media.AudioTrack? = null
            try {
                val rate = nativeAudioRate()
                val minBuf = android.media.AudioTrack.getMinBufferSize(
                    rate, android.media.AudioFormat.CHANNEL_OUT_STEREO,
                    android.media.AudioFormat.ENCODING_PCM_16BIT)
                // 2x min buffer: low latency (no late sound) with enough headroom.
                at = android.media.AudioTrack(
                    android.media.AudioAttributes.Builder()
                        .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                    android.media.AudioFormat.Builder()
                        .setEncoding(android.media.AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(rate)
                        .setChannelMask(android.media.AudioFormat.CHANNEL_OUT_STEREO)
                        .build(),
                    (minBuf * 2).coerceAtLeast(32 * 1024),
                    android.media.AudioTrack.MODE_STREAM, 0)
                at.play()
                while (running) {
                    val chunk = audioQueue.poll(80, java.util.concurrent.TimeUnit.MILLISECONDS)
                        ?: continue
                    try { at.write(chunk, 0, chunk.size) } catch (_: Exception) { break }
                    audioPool.offer(chunk) // recycle
                }
            } catch (e: Exception) {
                Log.w(TAG, "audio thread init failed: ${e.message}")
            }
            try { at?.stop(); at?.release() } catch (_: Exception) {}
        }
        emuThread = thread(name = "retro-run") {
            var bitmap: android.graphics.Bitmap? = null
            // Nearest-neighbor paint: crisp NES pixels AND much cheaper than bilinear.
            val paint = android.graphics.Paint().apply { isFilterBitmap = false }
            var pinned = false   // surface pinned to game size once (hardware upscale)
            var fpsAccum = 0L
            var fpsT0 = System.nanoTime()
            // Reused per-frame buffers (avoid GC pressure / allocation churn -> fps)
            var frameBuf: ByteArray? = null
            var frameBB: java.nio.ByteBuffer? = null
            while (running) {
                val t0 = System.nanoTime()
                nativeRunFrame()
                // Render the latest frame to the Surface if we have one.
                val w = nativeFrameWidth()
                val h = nativeFrameHeight()
                val pitch = nativeFramePitch()
                if (w > 0 && h > 0 && pitch > 0) {
                    val fmt = nativeFrameFormat()
                    val need = h * pitch
                    if (frameBuf == null || frameBuf!!.size != need) {
                        frameBuf = ByteArray(need)
                        frameBB = java.nio.ByteBuffer.wrap(frameBuf!!)
                    }
                    if (nativeCopyFrame(frameBuf!!) == 1) {
                        try {
                            val bmp = bitmap
                            if (bmp == null || bmp.width != w || bmp.height != h) {
                                val cfg = if (fmt == 2) android.graphics.Bitmap.Config.RGB_565
                                          else android.graphics.Bitmap.Config.ARGB_8888
                                bitmap = android.graphics.Bitmap.createBitmap(w, h, cfg)
                            }
                            frameBB!!.rewind() // copyPixelsFromBuffer consumes the buffer
                            bitmap?.copyPixelsFromBuffer(frameBB!!)
                            // Pin the surface buffer to the integer-scaled game size ONCE:
                            // the TV's compositor (hardware) upscales to full screen for
                            // free, and the CPU only does a small nearest-neighbor blit.
                            val sh = surfaceHolder
                            if (!pinned && sh != null) {
                                try {
                                    val sw = sh.surfaceFrame.width()
                                    val shh = sh.surfaceFrame.height()
                                    val s = (minOf(sw.toFloat() / w, shh.toFloat() / h)).toInt()
                                        .coerceAtLeast(1)
                                    sh.setFixedSize(w * s, h * s)
                                    pinned = true
                                } catch (_: Exception) {}
                            }
                            drawFrame(bitmap, paint, pinned)
                        } catch (e: Exception) {
                            // A bad frame must never kill the emulator — log and continue.
                            Log.w(TAG, "frame render skipped: ${e.message}")
                        }
                    }
                }
                // Queue audio for the audio thread (non-blocking; drop if it falls behind —
                // keeps sound snappy, never freezes video). Reuses pooled buffers: the
                // per-frame allocation was causing GC pauses (= video jank) on 32-bit TVs.
                try {
                    val n = nativeDrainAudio(audioBuf)
                    if (n > 0) {
                        var chunk = audioPool.poll()
                        if (chunk == null || chunk.size < n) chunk = ByteArray(n.coerceAtLeast(4096))
                        System.arraycopy(audioBuf, 0, chunk, 0, n)
                        if (!audioQueue.offer(chunk)) audioPool.offer(chunk) // full -> drop+recycle
                    }
                } catch (_: Exception) {}
                fpsAccum++
                val now = System.nanoTime()
                if (now - fpsT0 > 2_000_000_000L) {
                    Log.i(TAG, "fps=${fpsAccum * 1000L / ((now - fpsT0) / 1_000_000)}")
                    fpsAccum = 0; fpsT0 = now
                }
                val elapsed = (System.nanoTime() - t0)
                // Precise pacing: coarse Thread.sleep + sub-millisecond parkNanos.
                // Thread.sleep alone overshoots wildly on Android (a 2ms sleep can take
                // 8-15ms), which made the 60fps loop stutter between ~60 and ~45fps —
                // the "little laggy" feel even though fps looked fine.
                val sleepNs = 16_666_667L - elapsed
                if (sleepNs > 0) {
                    try {
                        Thread.sleep(sleepNs / 1_000_000L)
                        java.util.concurrent.locks.LockSupport.parkNanos(sleepNs % 1_000_000L)
                    } catch (_: InterruptedException) { break }
                }
            }
            audioQueue.clear()
        }
    }

    private val audioBuf = ByteArray(64 * 1024)

    @Volatile private var holderWidth = 0
    @Volatile private var holderHeight = 0

    /** Draw the game frame to the surface, preserving aspect ratio (no stretch). */
    private fun drawFrame(bmp: android.graphics.Bitmap?, paint: android.graphics.Paint, pinnedSurface: Boolean) {
        val holder = surfaceHolder ?: return
        val b = bmp ?: return
        val canvas = try { holder.lockCanvas() } catch (_: Exception) { return } ?: return
        try {
            holderWidth = canvas.width; holderHeight = canvas.height
            // Pinned surface: canvas == integer-scaled game size -> draw 1:1 (cheap blit),
            // no letterbox, no black fill needed (skips a full-canvas clear every frame).
            if (pinnedSurface && canvas.width % b.width == 0 && canvas.height % b.height == 0) {
                canvas.drawBitmap(b, null,
                    android.graphics.RectF(0f, 0f,
                        canvas.width.toFloat(), canvas.height.toFloat()), paint)
            } else {
                // Fallback (first frames before pinning): clear + center, aspect kept.
                canvas.drawColor(android.graphics.Color.BLACK)
                val vw = canvas.width.toFloat()
                val vh = canvas.height.toFloat()
                val ar = b.width.toFloat() / b.height.toFloat()
                var dw = vw
                var dh = vw / ar
                if (dh > vh) { dh = vh; dw = vh * ar }
                canvas.drawBitmap(b, null,
                    android.graphics.RectF((vw - dw) / 2f, (vh - dh) / 2f,
                        (vw + dw) / 2f, (vh + dh) / 2f), paint)
            }
        } finally {
            try { holder.unlockCanvasAndPost(canvas) } catch (_: Exception) {}
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
        "l2" -> BTN_L2; "r2" -> BTN_R2
        "dpad_up" -> BTN_UP; "dpad_down" -> BTN_DOWN
        "dpad_left" -> BTN_LEFT; "dpad_right" -> BTN_RIGHT
        else -> null
    }
}
