package app.headstart.push

import android.util.Log
import app.headstart.ServiceLocator
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

private const val TAG = "HsPush"

/**
 * Every alert decision is made on the server; this class only renders. It never invents a
 * push — in particular it never decides "arrived" (CLIENT_CONTRACT.md).
 *
 * [onMessageReceived] does nothing but hand the `data` map to [Notifications.deliver], the
 * shared renderer the debug injector also calls. Keep it that way: any logic added here
 * would be untested and unreachable from the AVD verification path.
 */
class HeadstartMessagingService : FirebaseMessagingService() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * firebase-messaging 25.x deprecates [onNewToken] in favour of [onRegistered] but still
     * dispatches it for the legacy `NEW_TOKEN` intent, so both are overridden and both feed
     * the one registration path. Exactly one of them fires per registration event.
     */
    @Deprecated("Deprecated in firebase-messaging 25.x; onRegistered is the v1 callback.")
    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onNewToken(token: String) {
        Log.i(TAG, "new FCM token (legacy callback)")
        scope.launch { registerToken(token) }
    }

    override fun onRegistered(token: String) {
        Log.i(TAG, "new FCM token")
        scope.launch { registerToken(token) }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        // A notification-payload push (e.g. a console test send) carries its text outside
        // `data`; fold it in so the one renderer sees a single uniform map.
        val data = HashMap(message.data)
        message.notification?.title?.let { data.putIfAbsent("title", it) }
        message.notification?.body?.let { data.putIfAbsent("body", it) }
        Notifications.deliver(this, data)
    }

    private suspend fun registerToken(token: String) {
        val uid = ServiceLocator.auth.currentUser?.uid
        if (uid == null) {
            // Not signed in yet: PushTokens.syncIfNeeded() re-registers after sign-in.
            Log.i(TAG, "token held until sign-in")
            return
        }
        runCatching { ServiceLocator.authRepository.registerPushToken(token) }
            .onSuccess { ServiceLocator.prefs.registeredTokenUid = uid }
            .onFailure { Log.w(TAG, "registerPushToken failed", it) }
    }
}

/**
 * Called after sign-in and after the display name is set, because `registerPushToken`
 * carries both the token and the name the other person sees in every alert.
 */
object PushTokens {
    @Suppress("DEPRECATION") // getInstance()/getToken(): the only way to read the token string in 25.x.
    suspend fun syncIfNeeded(displayName: String? = null, force: Boolean = false) {
        val uid = ServiceLocator.auth.currentUser?.uid ?: return
        if (!force && ServiceLocator.prefs.registeredTokenUid == uid && displayName == null) return
        try {
            val token = FirebaseMessaging.getInstance().token.await()
            ServiceLocator.authRepository.registerPushToken(token, displayName = displayName)
            ServiceLocator.prefs.registeredTokenUid = uid
        } catch (t: Throwable) {
            Log.w(TAG, "token sync failed", t)
        }
    }
}
