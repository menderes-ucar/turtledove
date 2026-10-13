package com.mndrs.turtledove

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject

/** Native FCM entry point for OS-level incoming-call handling. */
class BestieFirebaseMessagingService : FirebaseMessagingService() {

    companion object {
        const val NOTIFICATION_ID_BASE = 31000
        const val EXTRA_INCOMING_CALL = "bestie_incoming_call"
        const val PREFS = "bestie_call_state"
        const val PREF_PENDING_CALL = "pending_incoming_call"
        const val PREF_PENDING_NATIVE_ACTION = "pending_native_call_action"
        const val ACTION_CALL_ENDED = "com.mndrs.turtledove.action.CALL_ENDED"

        fun notificationId(callId: String): Int {
            var hash = 0
            for (ch in callId) hash = (hash * 31 + ch.code) and 0x7fffffff
            return if (hash == 0) NOTIFICATION_ID_BASE else hash
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val type = data["type"].orEmpty()
        val action = data["action"].orEmpty()

        if (type == "call_end" || action == "call_ended") {
            stopIncomingCall(data["call_id"].orEmpty())
            return
        }

        if (type != "call" && action != "incoming_call") return

        val callId = data["call_id"]?.takeIf { it.isNotBlank() } ?: return
        val payload = JSONObject().apply {
            data.forEach { (key, value) -> put(key, value) }
            put("type", data["type"] ?: "call")
            put("action", data["action"] ?: "incoming_call")
            put("call_id", callId)
        }.toString()

        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val appForeground = BestieApplication.isAppForeground()

        if (appForeground) {
            // When BESTIE has a started Activity, Flutter owns the foreground
            // incoming-call surface. Never start a second native surface.
            BestieCallRingingService.stop(this)
            prefs.edit()
                .remove(PREF_PENDING_CALL)
                .remove(PREF_PENDING_NATIVE_ACTION)
                .apply()
            return
        }

        prefs.edit()
            .putString(PREF_PENDING_CALL, payload)
            .apply()

        // Background/terminated app: the native call surface is the only
        // incoming UI. Flutter is launched only after the user taps Accept or
        // Reject, so the same call cannot create two incoming screens.
        BestieCallRingingService.start(this, payload)
    }

    private fun stopIncomingCall(callId: String) {
        BestieCallRingingService.stop(this)
        sendBroadcast(Intent(ACTION_CALL_ENDED).apply {
            setPackage(packageName)
            putExtra("call_id", callId)
        })
        if (callId.isNotBlank()) {
            getSystemService(NotificationManager::class.java)
                .cancel(BestieCallRingingService.NOTIFICATION_ID)
            getSystemService(NotificationManager::class.java)
                .cancel(notificationId(callId))
        }
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(PREF_PENDING_CALL)
            .remove(PREF_PENDING_NATIVE_ACTION)
            .apply()
    }
}
