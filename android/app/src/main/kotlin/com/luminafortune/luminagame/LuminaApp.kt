package com.luminafortune.luminagame

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.util.Log
import io.flutter.app.FlutterApplication

/**
 * Custom Application so the FCM display channel is registered as
 * IMPORTANCE_HIGH the moment the process is spawned — including
 * the case where FCM wakes the app from a fully killed state to
 * deliver a notification. Registering the channel only inside
 * MainActivity.onCreate would miss that path and the first push
 * of a cold-killed session would land on a low-priority default
 * channel.
 *
 * Registered via android:name in AndroidManifest.xml.
 */
class LuminaApp : FlutterApplication() {

    private val pushTag = "LF/PUSH-NATIVE"
    private val pushChannelId = "lf_glow_stream"
    private val pushChannelName = "Glow updates"
    private val pushChannelDesc = "News and offers about the game"

    override fun onCreate() {
        super.onCreate()
        ensurePushChannel()
    }

    private fun ensurePushChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            val existing = nm.getNotificationChannel(pushChannelId)
            if (existing != null) {
                Log.d(pushTag,
                    "app.channel.exists id=$pushChannelId " +
                        "importance=${existing.importance}")
                return
            }
            val channel = NotificationChannel(
                pushChannelId,
                pushChannelName,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = pushChannelDesc
                enableVibration(true)
                enableLights(true)
                setShowBadge(true)
                val sound: Uri? = RingtoneManager
                    .getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                if (sound != null) {
                    val attrs = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                    setSound(sound, attrs)
                }
            }
            nm.createNotificationChannel(channel)
            Log.d(pushTag, "app.channel.created id=$pushChannelId importance=HIGH")
        } catch (t: Throwable) {
            Log.w(pushTag, "app.channel.fail ${t.message}")
        }
    }
}
