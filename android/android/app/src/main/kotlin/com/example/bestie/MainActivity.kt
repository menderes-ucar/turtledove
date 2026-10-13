package com.example.bestie

import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "bestie/media_projection"
    private val systemChannel = "bestie/system"

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemChannel)
            .setMethodCallHandler { call, result ->
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
                                val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                                    data = android.net.Uri.parse("package:$packageName")
                                }
                                startActivity(intent)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("SETTINGS", e.message, null)
                }
            }

    }
}
