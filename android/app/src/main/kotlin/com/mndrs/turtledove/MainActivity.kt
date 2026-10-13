package com.mndrs.turtledove

import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "bestie/media_projection"
    private val systemChannel = "bestie/system"
    private var systemMethodChannel: MethodChannel? = null


    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val intent = Intent(this, MediaProjectionService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }

                    "stop" -> {
                        stopService(Intent(this, MediaProjectionService::class.java))
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }

        systemMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            systemChannel
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "openNotificationSettings" -> {
                            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            }
                            startActivity(intent)
                            result.success(true)
                        }

                        "openFullScreenSettings" -> {
                            if (Build.VERSION.SDK_INT >= 34) {
                                val intent = Intent(
                                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT
                                ).apply {
                                    data = android.net.Uri.parse("package:$packageName")
                                }
                                startActivity(intent)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        }

                        "getPendingIncomingCall" -> {
                            result.success(readPendingIncomingCall())
                        }

                        "cancelIncomingCallNotification" -> {
                            val callId = call.arguments?.toString()
                            if (!callId.isNullOrBlank()) {
                                cancelIncomingCallNotification(callId)
                            }
                            result.success(true)
                        }
                        "stopIncomingCallRinging" -> {
                            BestieCallRingingService.stop(this)
                            result.success(true)
                        }

                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("SETTINGS", e.message, null)
                }
            }
        }

        // If MainActivity was launched by the native full-screen call intent,
        // forward it to Flutter as soon as the engine is ready.
        // On cold start the Dart MethodChannel handler may not exist yet.
        // Leave native answer/reject in SharedPreferences and let
        // getPendingIncomingCall() deliver it after Flutter initializes.
        forwardIncomingCallIntent(intent, directNativeAction = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        forwardIncomingCallIntent(intent, directNativeAction = true)
    }

    private fun forwardIncomingCallIntent(intent: Intent?, directNativeAction: Boolean) {
        val payload = intent?.getStringExtra(
            BestieFirebaseMessagingService.EXTRA_INCOMING_CALL
        ) ?: return

        val data = payloadToMap(payload).toMutableMap()
        val nativeAction = intent.getStringExtra("bestie_call_action")
        if (nativeAction != null) {
            data["native_action"] = nativeAction
        }
        if (directNativeAction || nativeAction == null) {
            if (directNativeAction && nativeAction != null) {
                // The action was delivered directly through onNewIntent. Do
                // not let the same persisted native action be replayed by the
                // Dart cold-start recovery path.
                getSharedPreferences(BestieFirebaseMessagingService.PREFS, MODE_PRIVATE)
                    .edit()
                    .remove(BestieFirebaseMessagingService.PREF_PENDING_CALL)
                    .remove(BestieFirebaseMessagingService.PREF_PENDING_NATIVE_ACTION)
                    .apply()
            }
            systemMethodChannel?.invokeMethod("incomingCallIntent", data)
        }
    }

    private fun payloadToMap(payload: String): Map<String, String> {
        val json = org.json.JSONObject(payload)
        val result = mutableMapOf<String, String>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            result[key] = json.optString(key)
        }
        return result
    }

    private fun readPendingIncomingCall(): Map<String, String>? {
        val prefs = getSharedPreferences(
            BestieFirebaseMessagingService.PREFS,
            MODE_PRIVATE
        )
        val payload = prefs.getString(
            BestieFirebaseMessagingService.PREF_PENDING_CALL,
            null
        ) ?: return null

        return try {
            val result = payloadToMap(payload).toMutableMap()
            val nativeAction = prefs.getString(
                BestieFirebaseMessagingService.PREF_PENDING_NATIVE_ACTION,
                null
            )
            if (!nativeAction.isNullOrBlank()) {
                result["native_action"] = nativeAction
            }
            getSharedPreferences(
                BestieFirebaseMessagingService.PREFS,
                MODE_PRIVATE
            ).edit()
            .remove(BestieFirebaseMessagingService.PREF_PENDING_CALL)
            .remove(BestieFirebaseMessagingService.PREF_PENDING_NATIVE_ACTION)
            .apply()
            result
        } catch (_: Exception) {
            null
        }
    }

    private fun cancelIncomingCallNotification(callId: String) {
        val manager = getSystemService(android.app.NotificationManager::class.java)
        manager.cancel(BestieFirebaseMessagingService.notificationId(callId))

        getSharedPreferences(
            BestieFirebaseMessagingService.PREFS,
            MODE_PRIVATE
        ).edit()
            .remove(BestieFirebaseMessagingService.PREF_PENDING_CALL)
            .remove(BestieFirebaseMessagingService.PREF_PENDING_NATIVE_ACTION)
            .apply()
    }
}
