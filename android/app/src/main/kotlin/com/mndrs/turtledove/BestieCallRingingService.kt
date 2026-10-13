package com.mndrs.turtledove

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.IBinder

/**
 * Owns the OS-level incoming-call ringing state.
 *
 * The Flutter ringtone is deliberately not used for an incoming call because
 * the Flutter engine can be paused/killed while the call is ringing. This
 * service is started directly from the high-priority FCM callback and keeps a
 * looping ringtone + persistent CallStyle notification alive until the call
 * is answered, rejected or cancelled.
 */
class BestieCallRingingService : Service() {
    companion object {
        const val ACTION_START = "com.mndrs.turtledove.action.START_CALL_RINGING"
        const val ACTION_STOP = "com.mndrs.turtledove.action.STOP_CALL_RINGING"
        const val EXTRA_PAYLOAD = "bestie_call_payload"
        const val CHANNEL_ID = "bestie_calls_v4"
        const val NOTIFICATION_ID = 42001

        fun start(context: android.content.Context, payload: String) {
            val intent = Intent(context, BestieCallRingingService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_PAYLOAD, payload)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                android.util.Log.e("BESTIE_CALL", "ringing service start failed", e)
            }
        }

        fun stop(context: android.content.Context) {
            try {
                context.stopService(Intent(context, BestieCallRingingService::class.java))
            } catch (_: Exception) {}
        }
    }

    private var player: MediaPlayer? = null
    private var currentPayload: String = ""

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        val payload = intent?.getStringExtra(EXTRA_PAYLOAD)
        if (!payload.isNullOrBlank()) currentPayload = payload

        if (currentPayload.isBlank()) {
            stopSelf()
            return START_NOT_STICKY
        }

        startAsForeground(currentPayload)
        startRingtone()
        return START_NOT_STICKY
    }

    private fun startRingtone() {
        if (player?.isPlaying == true) return
        try {
            player?.release()
            val mp = MediaPlayer()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            val afd = resources.openRawResourceFd(R.raw.bestie_call_ringtone)
                ?: throw IllegalStateException("ringtone resource unavailable")
            afd.use {
                mp.setDataSource(it.fileDescriptor, it.startOffset, it.length)
            }
            mp.isLooping = true
            mp.prepare()
            mp.start()
            player = mp
        } catch (e: Exception) {
            android.util.Log.e("BESTIE_CALL", "ringtone start failed", e)
        }
    }

    private fun stopRingtone() {
        try { player?.stop() } catch (_: Exception) {}
        try { player?.release() } catch (_: Exception) {}
        player = null
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Turtle Dove Calls",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Incoming Bestie calls"
            // The foreground service owns the looping ringtone, so the channel
            // itself stays silent and cannot double-play a one-shot sound.
            setSound(null, null)
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun startAsForeground(payload: String) {
        val json = try { org.json.JSONObject(payload) } catch (_: Exception) { org.json.JSONObject() }
        val callId = json.optString("call_id", "bestie-call")
        val callerName = json.optString("caller_name").ifBlank { json.optString("title", "Turtle Dove") }
        val body = localizedIncomingLabel()

        val screenIntent = Intent(this, BestieIncomingCallActivity::class.java).apply {
            putExtra(BestieFirebaseMessagingService.EXTRA_INCOMING_CALL, payload)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val screenPending = PendingIntent.getActivity(
            this,
            callId.hashCode(),
            screenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val answerIntent = Intent(this, BestieIncomingCallActivity::class.java).apply {
            action = BestieIncomingCallActivity.ACTION_ANSWER
            putExtra(BestieFirebaseMessagingService.EXTRA_INCOMING_CALL, payload)
        }
        val answerPending = PendingIntent.getActivity(
            this,
            callId.hashCode() + 1,
            answerIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val rejectIntent = Intent(this, BestieIncomingCallActivity::class.java).apply {
            action = BestieIncomingCallActivity.ACTION_REJECT
            putExtra(BestieFirebaseMessagingService.EXTRA_INCOMING_CALL, payload)
        }
        val rejectPending = PendingIntent.getActivity(
            this,
            callId.hashCode() + 2,
            rejectIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(callerName)
            .setContentText(body)
            .setCategory(Notification.CATEGORY_CALL)
            .setPriority(Notification.PRIORITY_MAX)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(screenPending)
            .setFullScreenIntent(screenPending, true)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val caller = Person.Builder()
                .setName(callerName)
                .setImportant(true)
                .build()
            builder.setStyle(
                Notification.CallStyle.forIncomingCall(caller, rejectPending, answerPending)
            )
        } else {
            builder.addAction(Notification.Action.Builder(null, localizedDeclineLabel(), rejectPending).build())
            builder.addAction(Notification.Action.Builder(null, localizedAcceptLabel(), answerPending).build())
        }

        val notification = builder.build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun appLanguage(): String {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        return prefs.getString("flutter.app_locale", null)
            ?.lowercase()
            ?.take(2)
            ?: java.util.Locale.getDefault().language.lowercase().take(2)
    }

    private fun localizedIncomingLabel(): String = when (appLanguage()) {
        "tr" -> "Gelen arama"
        "de" -> "Eingehender Anruf"
        "es" -> "Llamada entrante"
        "fr" -> "Appel entrant"
        else -> "Incoming call"
    }

    private fun localizedAcceptLabel(): String = when (appLanguage()) {
        "tr" -> "Kabul et"
        "de" -> "Annehmen"
        "es" -> "Aceptar"
        "fr" -> "Accepter"
        else -> "Accept"
    }

    private fun localizedDeclineLabel(): String = when (appLanguage()) {
        "tr" -> "Reddet"
        "de" -> "Ablehnen"
        "es" -> "Rechazar"
        "fr" -> "Refuser"
        else -> "Decline"
    }

    override fun onDestroy() {
        stopRingtone()
        val manager = getSystemService(NotificationManager::class.java)
        manager.cancel(NOTIFICATION_ID)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
