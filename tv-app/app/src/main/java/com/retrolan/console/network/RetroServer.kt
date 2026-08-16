package com.retrolan.console.network

import com.retrolan.console.core.LibRetro
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.routing.*
import io.ktor.server.websocket.*
import io.ktor.websocket.*
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import java.net.InetSocketAddress

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

    private var engine: EmbeddedServer<*, *>? = null
    @Volatile var onControllerCount: ((Int) -> Unit)? = null
    private val controllers = mutableSetOf<WebSocketSession>()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    @Synchronized
    fun start() {
        if (engine != null) return
        val name = android.os.Build.MODEL
        engine = embeddedServer(Netty, host = "0.0.0.0", port = PORT) {
            install(WebSockets)
            routing {
                webSocket("/") { handle(this, name) }
            }
        }
        scope.launch { engine?.start(wait = false) }
    }

    private suspend fun handle(ws: DefaultWebSocketSession, name: String) {
        controllers.add(ws)
        onControllerCount?.invoke(controllers.size)
        try {
            ws.send(jsonString("hello_ack", mapOf("name" to name, "cores" to listOf("fceumm","snes9x","gambatte"))))
            for (frame in ws.incoming) {
                if (frame !is Frame.Text) continue
                val text = frame.readText()
                process(text, ws)
            }
        } catch (_: Exception) {
            // disconnected
        } finally {
            controllers.remove(ws)
            onControllerCount?.invoke(controllers.size)
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
        scope.cancel()
        engine?.stop(1000, 5000)
        engine = null
    }
}
