package com.retrolan.console.network

import com.retrolan.console.core.LibRetro
import io.ktor.server.application.*
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.*
import io.ktor.server.routing.*
import io.ktor.server.websocket.*
import io.ktor.websocket.*
import kotlinx.coroutines.*
import kotlinx.serialization.json.*

/**
 * Embedded WebSocket server (role of the TV host).
 *
 * Listens on TCP 8877, implements the RetroLAN JSON protocol from /protocol/PROTOCOL.md.
 * Input messages are routed straight into the libretro core's joypad state via [LibRetro.press].
 *
 * This file is RetroLAN-original code (GPLv3 under /tv-app).
 */
object RetroServer {
    private const val TAG = "RetroServer"
    private const val PORT = 8877
    private const val MAX_PLAYERS = 2

    @Volatile var onControllerCount: ((Int) -> Unit)? = null
    @Volatile var onRomReceived: ((String) -> Unit)? = null   // called with saved filename after upload
    @Volatile var romDir: java.io.File? = null                // where sent ROMs are saved (app files dir)
    private val controllers = mutableSetOf<WebSocketSession>()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // The emulator process (:emulator) connects back here as a relay client; every
    // controller input is forwarded to it so the core (in that process) receives it.
    @Volatile private var relay: WebSocketSession? = null

    // Started/stopped via the running job on the app scope; no typed engine field needed.
    private var state = State.IDLE
    private enum class State { IDLE, RUNNING, STOPPED }

    @Synchronized
    fun start() {
        if (state == State.RUNNING) return
        state = State.RUNNING
        val name = android.os.Build.MODEL
        val server = embeddedServer(Netty, host = "0.0.0.0", port = PORT) {
            install(WebSockets)
            routing {
                webSocket("/") { handle(this, name) }
            }
        }
        scope.launch {
            try {
                server.start(wait = true) // blocks until stopped; runs on this coroutine
            } catch (_: Exception) {}
        }
    }

    private suspend fun handle(ws: DefaultWebSocketSession, name: String) {
        controllers.add(ws)
        onControllerCount?.invoke(controllers.size)
        // Pending ROM upload state (filename -> accumulating bytes)
        var uploadName: String? = null
        val uploadBytes = java.io.ByteArrayOutputStream()
        var isRelay = false
        try {
            ws.send(jsonString("hello_ack", mapOf("name" to name, "cores" to com.retrolan.console.core.Cores.defaultHelloCores)))
            for (frame in ws.incoming) {
                when (frame) {
                    is Frame.Text -> {
                        val text = frame.readText()
                        // Parse JSON header
                        try {
                            val obj = Json.parseToJsonElement(text).jsonObject
                            when (obj["type"]?.jsonPrimitive?.content) {
                                "hello" -> {
                                    // The emulator process identifies itself as a relay; from
                                    // then on it receives copies of every controller input.
                                    val role = obj["role"]?.jsonPrimitive?.content
                                    if (role == "emulator-relay") { isRelay = true; relay = ws }
                                }
                                "rom_upload" -> {
                                    val nm = obj["name"]?.jsonPrimitive?.content
                                    if (!nm.isNullOrEmpty()) { uploadName = nm; uploadBytes.reset() }
                                }
                                "rom_end" -> {
                                    // Finished receiving a ROM — save + play now (connection still open).
                                    val nm = uploadName
                                    val bytes = uploadBytes.toByteArray()
                                    if (nm != null && bytes.isNotEmpty()) {
                                        saveAndPlay(nm, bytes, ws)
                                        uploadName = null; uploadBytes.reset()
                                    }
                                }
                                else -> process(text, ws)
                            }
                        } catch (_: Exception) {}
                    }
                    is Frame.Binary -> {
                        val bytes = frame.readBytes()
                        if (uploadName != null) uploadBytes.write(bytes)
                    }
                    else -> {}
                }
            }
        } catch (_: Exception) {
            // disconnected
        } finally {
            // On close, if we received a full ROM, save + play it.
            if (uploadName != null && uploadBytes.size() > 0) {
                saveAndPlay(uploadName!!, uploadBytes.toByteArray(), ws)
            }
            if (isRelay && relay == ws) relay = null
            controllers.remove(ws)
            // A controller left mid-press — release its buttons so the game doesn't
            // think a button is held forever (fixes "auto-jump" after disconnect).
            if (!isRelay) {
                relay?.let { r ->
                    if (r.isActive) {
                        try { r.send("""{"type":"control","action":"release_all"}""") } catch (_: Exception) {}
                    }
                }
            }
            onControllerCount?.invoke(controllers.size)
        }
    }

    /** Save a received ROM to the app's own files dir and auto-load + play it. */
    private suspend fun saveAndPlay(name: String, bytes: ByteArray, ws: DefaultWebSocketSession) {
        try {
            val dir = romDir ?: android.os.Environment.getExternalStorageDirectory()
            dir.mkdirs()
            val safe = name.replace("../", "_").replace("/", "_")
            val out = java.io.File(dir, safe)
            out.writeBytes(bytes)
            android.util.Log.i(TAG, "received ROM $name (${bytes.size} B) -> ${out.absolutePath}")
            ws.send(jsonString("rom_ack", mapOf("name" to safe, "size" to bytes.size)))
            onRomReceived?.invoke(safe)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "save ROM failed: ${e.message}")
        }
    }

    private suspend fun process(text: String, ws: DefaultWebSocketSession) {
        val obj = try { Json.parseToJsonElement(text).jsonObject } catch (_: Exception) {
            ws.send(jsonString("error", mapOf("code" to "malformed", "message" to "invalid JSON"))); return
        }
        when (obj["type"]?.jsonPrimitive?.content) {
            "hello" -> { /* acknowledged; player set is discarded here, kept server-side */ }
            "input" -> {
                val player = (obj["player"]?.jsonPrimitive?.int ?: 1).coerceIn(1, MAX_PLAYERS)
                val button = obj["button"]?.jsonPrimitive?.content ?: return
                val down = obj["state"]?.jsonPrimitive?.content == "down"
                if (LibRetro.buttonToLibretro(button) == null) {
                    ws.send(jsonString("error", mapOf("code" to "invalid_button", "message" to "unknown button '$button'")))
                    return
                }
                LibRetro.press(button, down, player)
                // Forward to the emulator process relay (the core lives there now).
                relay?.let { r ->
                    if (r != ws && r.isActive) {
                        try { r.send(text) } catch (_: Exception) {}
                    }
                }
            }
            "control" -> {
                // Back / close-game commands from the controller, forwarded to the
                // emulator process (which finishes the game activity).
                val action = obj["action"]?.jsonPrimitive?.content ?: return
                relay?.let { r ->
                    if (r.isActive) {
                        try { r.send(text) } catch (_: Exception) {}
                    }
                }
                if (action == "close") LibRetro.clearButtons()
            }
            "ping" -> {
                val ts = obj["ts"]?.jsonPrimitive?.longOrNull ?: System.currentTimeMillis()
                ws.send(jsonString("pong", mapOf("ts" to ts)))
            }
        }
    }

    private fun jsonString(type: String, payload: Map<String, Any?>): String {
        return buildJsonObject {
            put("type", type)
            payload.forEach { (k, v) ->
                when (v) {
                    is String -> put(k, v)
                    is Int -> put(k, v)
                    is Long -> put(k, v)
                    is Boolean -> put(k, v)
                    is List<*> -> put(k, JsonArray(v.filterIsInstance<String>().map { JsonPrimitive(it) }))
                }
            }
        }.toString()
    }

    @Synchronized
    fun stop() {
        state = State.STOPPED
        scope.cancel()
    }
}
