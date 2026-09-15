package com.telichat.mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentResolver
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import io.flutter.app.FlutterApplication

class MainApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val soundUri = Uri.parse("${ContentResolver.SCHEME_ANDROID_RESOURCE}://${packageName}/raw/alarm_clock")
            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_ALARM)
                .build()

            // 1. High Priority Alarm Channel for Market Price Touches & Critical Alerts
            val channelId = "gold_price_alerts_v5"
            val channelName = "🚨 High Priority Price Level Alarms"
            val channelDesc = "Loud alarm clock notifications for market price touches"
            val importance = NotificationManager.IMPORTANCE_HIGH

            val alarmChannel = NotificationChannel(channelId, channelName, importance).apply {
                description = channelDesc
                enableLights(true)
                lightColor = 0xFFF59E0B.toInt()
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
                setSound(soundUri, audioAttributes)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                setBypassDnd(true)
                setShowBadge(true)
            }

            // 2. Standard Market Notification Channel
            val standardChannel = NotificationChannel(
                "gold_alerts_channel_standard",
                "🔔 Market Price Touch Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Instant notification alerts when market touches custom target price"
                enableLights(true)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 800, 400, 800)
                setSound(soundUri, audioAttributes)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                setShowBadge(true)
            }

            // 3. Vibration Only Alarm Channel (No Sound)
            val vibrateChannel = NotificationChannel(
                "gold_price_alerts_vibrate_only",
                "📳 Price Level Alarms (Vibrate Only)",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Vibration only alerts without sound for market price touches"
                enableLights(true)
                lightColor = 0xFFF59E0B.toInt()
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
                setSound(null, null)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                setShowBadge(true)
            }

            // 4. Foreground Monitoring Service Channel (Silent/Ongoing)
            val serviceChannel = NotificationChannel(
                "gold_background_service_channel",
                "📊 Market Price Guard (Foreground Service)",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Ongoing 24/7 background price monitoring service"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(alarmChannel)
            manager?.createNotificationChannel(standardChannel)
            manager?.createNotificationChannel(vibrateChannel)
            manager?.createNotificationChannel(serviceChannel)
        }
    }
}
