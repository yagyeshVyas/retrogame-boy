package com.retrolan.console.network

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import com.retrolan.console.R
import com.retrolan.console.ui.MainActivity
import com.retrolan.console.core.LibRetro

/**
 * Keeps the WebSocket server alive in the main process while a game is running in the
 * :emulator process. Without a foreground service, Android's memory manager kills the
 * main (background) process after ~1-2 minutes of gameplay — killing the WS server and
 * leaving the phone controller stuck reconnecting forever.
 */
class RetroLanService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundCompat()
        RetroServer.start() // WS server on :8877 (handles input -> LibRetro.press)
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        RetroServer.stop()
    }

    private fun startForegroundCompat() {
        val chId = "retrolan_server"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(chId, "RetroLAN server", NotificationManager.IMPORTANCE_LOW)
            ch.setShowBadge(false)
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE)
        val n: Notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, chId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
            .setSmallIcon(R.drawable.ic_banner)
            .setContentTitle("RetroLAN Console")
            .setContentText("Game server running — connect your phone controller")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(1, n, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(1, n)
        }
    }
}
