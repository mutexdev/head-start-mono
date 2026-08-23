package app.headstart.debug

import android.app.Activity
import android.app.Application
import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.util.Log
import app.headstart.BuildConfig
import app.headstart.ServiceLocator
import app.headstart.core.HeadstartConfig
import app.headstart.push.Notifications
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.Query

/**
 * The `_debugPushes` bridge the contract addendum makes mandatory on both clients.
 *
 * FCM cannot deliver from the Firebase emulator, so the server's `PushSender` writes every
 * would-be push to `_debugPushes/{autoId}` instead. This listener watches the rows addressed
 * to the signed-in user and feeds each new one into [Notifications.deliver] — the SAME
 * renderer a real FCM message takes, same `data.kind` switch, same channel.
 *
 * Division of labour, per the addendum: the broadcast injector validates *rendering* of all
 * thirteen kinds; this bridge validates the *server's decisions* — that the alert ladder
 * fires the kinds it should, when it should. Both are required.
 *
 * Debug source set only, so it cannot exist in a release build, and additionally gated on
 * [HeadstartConfig.useLocalEmulators] — pointed at the real cloud there is no sink to read.
 *
 * Row shape written by the server:
 * ```
 * { toUid, kind, title, body, urgent, data{kind, tripId?}, androidChannelId,
 *   apnsInterruptionLevel, tokens, sentAt, delivered:false }
 * ```
 */
object DebugPushBridge {

    private const val TAG = "HsDebugPush"
    private const val COLLECTION = "_debugPushes"

    private var registration: ListenerRegistration? = null
    private var listeningUid: String? = null
    /** Rows that already existed when the listener attached are history, not new alerts. */
    private var primed = false

    private val authListener = FirebaseAuth.AuthStateListener { auth ->
        attach(auth.currentUser?.uid)
    }

    fun start() {
        if (!BuildConfig.DEBUG || !HeadstartConfig.useLocalEmulators) {
            Log.i(TAG, "_debugPushes bridge inactive (release build or cloud mode)")
            return
        }
        Log.i(TAG, "_debugPushes bridge armed; waiting for sign-in")
        ServiceLocator.auth.addAuthStateListener(authListener)
    }

    private fun attach(uid: String?) {
        if (uid == listeningUid) return
        registration?.remove()
        registration = null
        listeningUid = uid
        primed = false
        if (uid == null) {
            Log.i(TAG, "signed out; _debugPushes listener detached")
            return
        }
        Log.i(TAG, "_debugPushes listener attached for $uid")
        registration = ServiceLocator.db.collection(COLLECTION)
            .whereEqualTo("toUid", uid)
            .orderBy("sentAt", Query.Direction.ASCENDING)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    // Expected until the backend ships firestore.rules for _debugPushes,
                    // and expected forever when no emulator suite is running.
                    Log.w(TAG, "_debugPushes listener failed: ${error.message}")
                    return@addSnapshotListener
                }
                if (snapshot == null) return@addSnapshotListener
                if (!primed) {
                    primed = true
                    Log.i(TAG, "primed with ${snapshot.size()} historical rows")
                    return@addSnapshotListener
                }
                for (change in snapshot.documentChanges) {
                    if (change.type != com.google.firebase.firestore.DocumentChange.Type.ADDED) continue
                    render(change.document.data)
                }
            }
    }

    @Suppress("UNCHECKED_CAST")
    private fun render(row: Map<String, Any?>) {
        val data = HashMap<String, String>()
        (row["data"] as? Map<String, Any?>)?.forEach { (k, v) ->
            if (v != null) data[k] = v.toString()
        }
        (row["kind"] as? String)?.let { data["kind"] = it }
        (row["title"] as? String)?.let { data["title"] = it }
        (row["body"] as? String)?.let { data["body"] = it }
        Log.i(TAG, "server push replayed: $data")
        Notifications.deliver(ServiceLocator.appContext, data)
    }
}

/**
 * Starts [DebugPushBridge] without any main-source-set edit — the debug variant must not
 * require a line in `HeadstartApp`, or the bridge could not stay out of a release build.
 *
 * A ContentProvider is created before `Application.onCreate`, which is too early to touch
 * Firebase (`ServiceLocator.init` has not run and `HeadstartConfig.wire` must be the first
 * Firebase call this process makes). So this only registers an activity-lifecycle callback
 * and attaches on the first activity start, which is comfortably after that.
 */
class DebugPushBridgeInitializer : ContentProvider() {

    override fun onCreate(): Boolean {
        val app = context?.applicationContext as? Application ?: return false
        app.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            private var started = false
            override fun onActivityStarted(activity: Activity) {
                if (started) return
                started = true
                runCatching { DebugPushBridge.start() }
                    .onFailure { Log.w("HsDebugPush", "bridge start failed", it) }
            }

            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
            override fun onActivityResumed(activity: Activity) = Unit
            override fun onActivityPaused(activity: Activity) = Unit
            override fun onActivityStopped(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
            override fun onActivityDestroyed(activity: Activity) = Unit
        })
        return true
    }

    override fun query(u: Uri, p: Array<out String>?, s: String?, a: Array<out String>?, o: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, s: String?, a: Array<out String>?): Int = 0
    override fun update(uri: Uri, v: ContentValues?, s: String?, a: Array<out String>?): Int = 0
}
