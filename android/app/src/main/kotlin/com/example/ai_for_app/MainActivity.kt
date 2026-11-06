package com.example.ai_for_app

import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object { var backgroundChannel: MethodChannel? = null; var foreground = false }
    override fun provideFlutterEngine(context: Context): FlutterEngine? = FlutterEngineCache.getInstance().get("local_ai")
    override fun shouldDestroyEngineWithHost(): Boolean = false
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FlutterEngineCache.getInstance().put("local_ai", flutterEngine)
        backgroundChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ai_for_app/background_execution").also { channel ->
            channel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "begin" -> { startForegroundService(Intent(applicationContext, InferenceService::class.java)); result.success(null) }
                        "end" -> { stopService(Intent(applicationContext, InferenceService::class.java)); result.success(null) }
                        "progress" -> result.success(null)
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) { result.error("background_unavailable", error.message, null) }
            }
        }
    }
    override fun onPause() {
        foreground = false
        super.onPause()
    }
    override fun onResume() {
        super.onResume()
        foreground = true
        backgroundChannel?.invokeMethod("resumed", null)
    }
}
