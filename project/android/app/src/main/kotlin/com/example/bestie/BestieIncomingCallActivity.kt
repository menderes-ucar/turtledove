package com.example.bestie

import android.app.Activity
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** Native full-screen fallback for incoming calls when Android grants the app
 * the full-screen-intent capability. CallStyle remains the notification
 * fallback when the OS/user does not allow full-screen UI. */
class BestieIncomingCallActivity : Activity() {
    companion object {
        const val ACTION_ANSWER = "com.example.bestie.action.ANSWER_CALL"
        const val ACTION_REJECT = "com.example.bestie.action.REJECT_CALL"
    }

    private var payload: String = ""
    private val callEndedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != BestieFirebaseMessagingService.ACTION_CALL_ENDED) return
            val endedCallId = intent.getStringExtra("call_id").orEmpty()
            val currentCallId = try {
                org.json.JSONObject(payload).optString("call_id")
            } catch (_: Exception) {
                ""
            }
            if (endedCallId.isNotBlank() && endedCallId == currentCallId) {
                finish()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(BestieFirebaseMessagingService.ACTION_CALL_ENDED)
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            registerReceiver(callEndedReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(callEndedReceiver, filter)
        }
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
        )
        if (android.os.Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }

        payload = intent?.getStringExtra(BestieFirebaseMessagingService.EXTRA_INCOMING_CALL).orEmpty()
        when (intent?.action) {
            ACTION_ANSWER -> answer()
            ACTION_REJECT -> reject()
            else -> render()
        }
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        payload = intent?.getStringExtra(BestieFirebaseMessagingService.EXTRA_INCOMING_CALL).orEmpty()
        when (intent?.action) {
            ACTION_ANSWER -> answer()
            ACTION_REJECT -> reject()
            else -> render()
        }
    }

    private fun render() {
        val json = try { org.json.JSONObject(payload) } catch (_: Exception) { org.json.JSONObject() }
        val callerName = json.optString("caller_name").ifBlank { json.optString("title", "Bestie") }
        val strings = localizedCallStrings()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(40, 60, 40, 60)
            setBackgroundColor(Color.rgb(10, 15, 20))
        }

        val name = TextView(this).apply {
            text = callerName
            textSize = 30f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }
        val subtitle = TextView(this).apply {
            text = strings.incoming
            textSize = 18f
            setTextColor(Color.LTGRAY)
            gravity = Gravity.CENTER
            setPadding(0, 16, 0, 48)
        }

        val answer = Button(this).apply {
            text = strings.accept
            setOnClickListener { answer() }
        }
        val reject = Button(this).apply {
            text = strings.decline
            setOnClickListener { reject() }
        }

        root.addView(name, LinearLayout.LayoutParams(-1, -2))
        root.addView(subtitle, LinearLayout.LayoutParams(-1, -2))
        root.addView(answer, LinearLayout.LayoutParams(-1, -2))
        root.addView(reject, LinearLayout.LayoutParams(-1, -2))
        setContentView(root)
    }

    private data class CallStrings(
        val incoming: String,
        val accept: String,
        val decline: String,
    )

    private fun localizedCallStrings(): CallStrings {
        // Flutter's LocaleProvider persists the selected app language in the
        // standard shared_preferences XML. Read that same value so the native
        // incoming-call screen uses the app language rather than hard-coded
        // English labels.
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val code = prefs.getString("flutter.app_locale", null)
            ?.lowercase()
            ?.take(2)
            ?: java.util.Locale.getDefault().language.lowercase().take(2)

        return when (code) {
            "tr" -> CallStrings("Gelen arama", "Kabul et", "Reddet")
            "de" -> CallStrings("Eingehender Anruf", "Annehmen", "Ablehnen")
            "es" -> CallStrings("Llamada entrante", "Aceptar", "Rechazar")
            "fr" -> CallStrings("Appel entrant", "Accepter", "Refuser")
            else -> CallStrings("Incoming call", "Accept", "Decline")
        }
    }

    override fun onDestroy() {
        try { unregisterReceiver(callEndedReceiver) } catch (_: Exception) {}
        super.onDestroy()
    }

    private fun answer() {
        finishRinging("accept")
        launchFlutter("accept")
    }

    private fun reject() {
        finishRinging("reject")
        launchFlutter("reject")
    }

    private fun finishRinging(nativeAction: String) {
        BestieCallRingingService.stop(this)
        val callId = try { org.json.JSONObject(payload).optString("call_id") } catch (_: Exception) { "" }
        if (callId.isNotBlank()) {
            getSystemService(android.app.NotificationManager::class.java)
                .cancel(BestieFirebaseMessagingService.notificationId(callId))
        }
        // Keep the payload until Flutter consumes it. This avoids a cold-start
        // race where MainActivity is created before the Dart MethodChannel
        // handler is registered. The action is persisted alongside the payload
        // so one native tap is sufficient to enter/reject the call.
        getSharedPreferences(BestieFirebaseMessagingService.PREFS, MODE_PRIVATE)
            .edit()
            .putString(BestieFirebaseMessagingService.PREF_PENDING_NATIVE_ACTION, nativeAction)
            .apply()
    }

    private fun launchFlutter(action: String) {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(BestieFirebaseMessagingService.EXTRA_INCOMING_CALL, payload)
            putExtra("bestie_call_action", action)
        }
        startActivity(intent)
        finish()
    }
}
