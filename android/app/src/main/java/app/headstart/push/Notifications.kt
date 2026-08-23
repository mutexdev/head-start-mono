package app.headstart.push

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import app.headstart.MainActivity
import app.headstart.R
import app.headstart.tracking.LocationForegroundService

/**
 * Two channels, exactly as CLIENT_CONTRACT.md specifies:
 *  - `sync_urgent`  IMPORTANCE_HIGH, own sound, tries to bypass Do Not Disturb.
 *    Only `leadTime` — the walk-out alert — ever uses it.
 *  - `sync_updates` IMPORTANCE_DEFAULT. Everything else, including the ongoing trip.
 *
 * Keeping the loud channel scarce is the product decision that makes it mean something.
 *
 * Channels are created exactly ONCE, from `HeadstartApp.onCreate`. (The plan's Task 15
 * comment claiming they are created "in Task 17" is stale — Task 17 is the receiver
 * screens. Resolved by the addendum arbitration; see the batch brief.)
 *
 * All routing lives in [PushRouting.kt] so it is JVM-testable and so the debug injector and
 * the real FCM service share one code path. This file is the android.* half only.
 */
object Notifications {

    private const val TAG = "HsPush"

    fun createChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return

        val urgent = NotificationChannel(
            CHANNEL_URGENT,
            "Walk out now",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "The one alert that tells you to leave the building. Loud on purpose."
            enableVibration(true)
            // A distinct tone so this never sounds like an ordinary notification. A bundled
            // sound file lands in M4; the alarm tone is the closest stock alternative.
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            // Only honoured if the user grants Do Not Disturb access; harmless otherwise.
            setBypassDnd(true)
        }

        val updates = NotificationChannel(
            CHANNEL_UPDATES,
            "Trip updates",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Started driving, ten minutes away, delays, arrival, replies."
        }

        manager.createNotificationChannel(urgent)
        manager.createNotificationChannel(updates)
    }

    private fun openAppIntent(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    /**
     * The ongoing notification the foreground service is legally required to show.
     * `Notification.ProgressStyle` is API 36+; below that the classic determinate
     * progress bar carries the same information.
     */
    fun ongoingTrip(
        context: Context,
        title: String,
        body: String,
        progressPct: Int? = null,
    ): Notification {
        val builder = NotificationCompat.Builder(context, CHANNEL_UPDATES)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openAppIntent(context))

        val pct = progressPct?.coerceIn(0, 100)
        if (pct != null) {
            if (Build.VERSION.SDK_INT >= 36) {
                builder.setStyle(
                    NotificationCompat.ProgressStyle()
                        .addProgressSegment(NotificationCompat.ProgressStyle.Segment(100))
                        .setProgress(pct),
                )
            } else {
                builder.setProgress(100, pct, false)
            }
        }
        return builder.build()
    }

    /**
     * Renders one incoming push. The ONLY entry point for both the real FCM service and
     * the debug injector, so what a reviewer verifies on the AVD is what ships.
     */
    fun deliver(context: Context, data: Map<String, String>) {
        val spec = renderSpec(data)
        Log.i(TAG, "push kind=${spec.kind} channel=${spec.channelId} id=${spec.notificationId}")

        if (spec.hasText) showAlert(context, spec)
        if (spec.raisesNudgeSheet) NudgeBus.raise()
        if (spec.endsTracking) LocationForegroundService.stop(context)
    }

    private fun showAlert(context: Context, spec: PushRenderSpec) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val notification = NotificationCompat.Builder(context, spec.channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(spec.title)
            .setContentText(spec.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(spec.body))
            .setAutoCancel(true)
            .setPriority(
                if (spec.urgent) NotificationCompat.PRIORITY_MAX else NotificationCompat.PRIORITY_DEFAULT,
            )
            .setCategory(
                if (spec.urgent) NotificationCompat.CATEGORY_ALARM else NotificationCompat.CATEGORY_MESSAGE,
            )
            .setContentIntent(openAppIntent(context))
            .build()
        manager.notify(spec.notificationId, notification)
    }
}
