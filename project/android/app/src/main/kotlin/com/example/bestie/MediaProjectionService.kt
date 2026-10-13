package com.example.bestie

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

class MediaProjectionService : Service() {
    companion object {
        private const val CHANNEL_ID = "bestie_screen_share_v2"
        private const val NOTIFICATION_ID = 7401
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("BESTIE call")
            .setContentText("Screen sharing is active")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_CALL)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "BESTIE call",
            NotificationManager.IMPORTANCE_LOW
        )
        channel.description = "Active call and screen sharing"
        manager.createNotificationChannel(channel)
    }
}
