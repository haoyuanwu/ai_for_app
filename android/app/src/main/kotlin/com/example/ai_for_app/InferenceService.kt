package com.example.ai_for_app

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.*

/** A visible, user-initiated CPU processing task, never an idle keep-alive. */
class InferenceService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("local_inference", "本地 AI 后台处理", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(this, "local_inference")
            .setSmallIcon(R.drawable.ic_stat_reminder)
            .setContentTitle("本地 AI 正在处理")
            .setContentText("正在处理对话或图片，完成后自动结束")
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true).build()
        startForeground(4101, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        wakeLock = (getSystemService(POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:inference").apply {
            setReferenceCounted(false)
            acquire(6 * 60 * 60 * 1000L)
        }
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_NOT_STICKY
    override fun onBind(intent: Intent?) = null
    override fun onTimeout(startId: Int, fgsType: Int) {
        MainActivity.backgroundChannel?.invokeMethod(if (MainActivity.foreground) "resumed" else "expired", null)
        stopSelf()
    }
    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
