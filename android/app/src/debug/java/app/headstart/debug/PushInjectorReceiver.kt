package app.headstart.debug

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import app.headstart.BuildConfig
import app.headstart.push.Notifications

/**
 * Debug-variant-only stand-in for an incoming FCM message.
 *
 * There is no way to send a real FCM message from a dev machine without a service-account
 * key (`firebase-tools` has no `messaging:send`), so `data.kind` rendering — the entire
 * point of the two-channel contract — would otherwise be unverifiable. This receiver turns
 * `adb` string extras into the same `Map<String, String>` the real
 * `HeadstartMessagingService` builds and hands it to the SAME renderer
 * ([Notifications.deliver]), so the path a reviewer exercises is the path that ships.
 *
 * `android:exported="true"` is required because `am broadcast` runs as the shell uid. It
 * lives only in `app/src/debug/`, so it cannot exist in a release build; the
 * [BuildConfig.DEBUG] guard is the second lock.
 *
 * Verify (Pixel_9a AVD, app installed and launched at least once):
 * ```
 * adb -s emulator-5554 shell am broadcast \
 *   -n app.headstart/app.headstart.debug.PushInjectorReceiver \
 *   -a app.headstart.DEBUG_PUSH \
 *   -e kind leadTime -e title "Start walking now" -e body "Alex is 3 min away"
 * ```
 * expect `Broadcast completed: result=0` and a heads-up notification on `sync_urgent`:
 * ```
 * adb -s emulator-5554 shell dumpsys notification --noredact | grep sync_urgent
 * ```
 * Swap `-e kind tenMin` and the same record must land on `sync_updates` instead. Any of the
 * thirteen contract kinds works, plus `-e tripId <id>` for the trip-scoped ones.
 */
class PushInjectorReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (!BuildConfig.DEBUG) return
        if (intent.action != ACTION) {
            Log.w(TAG, "ignoring unexpected action ${intent.action}")
            return
        }

        val data = HashMap<String, String>()
        val extras = intent.extras
        if (extras != null) {
            for (key in extras.keySet()) {
                val value = extras.getString(key) ?: continue
                data[key] = value
            }
        }
        Log.i(TAG, "injecting fake push: $data")
        Notifications.deliver(context.applicationContext, data)
    }

    private companion object {
        const val TAG = "HsPushInject"
        const val ACTION = "app.headstart.DEBUG_PUSH"
    }
}
