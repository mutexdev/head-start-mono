package app.headstart.core

import android.util.Log
import app.headstart.BuildConfig
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.functions.FirebaseFunctions

/**
 * Where this build's Firebase calls go.
 *
 * Not in the plan doc, and required: Cloud Functions cannot be deployed from this machine
 * (Blaze billing is unconfirmed) and there is no real SMS, so debug builds talk to the
 * Firebase Local Emulator Suite instead. Ports are fixed by the M1 contract addendum:
 * auth 9099, firestore 8080, functions 5001.
 *
 * Release builds never touch this path — [useLocalEmulators] is gated on `BuildConfig.DEBUG`.
 */
object HeadstartConfig {
    // 10.0.2.2 is the Android emulator's alias for the host machine's loopback.
    // `localhost` inside an AVD is the guest itself, which listens to nothing.
    private const val EMULATOR_HOST = "10.0.2.2"
    const val AUTH_PORT = 9099
    const val FIRESTORE_PORT = 8080
    const val FUNCTIONS_PORT = 5001

    const val LOG_TAG = "Headstart"

    /**
     * Runtime override so a reviewer can point a debug build at the real cloud without a
     * rebuild. Fed from `Prefs.useCloud` (SharedPreferences key `headstart_use_cloud`,
     * settable with `adb shell` or the debug Settings row) by `ServiceLocator.init`.
     */
    @Volatile
    var useCloudOverride: Boolean = false

    /** Debug builds default to the Firebase Local Emulator Suite. */
    val useLocalEmulators: Boolean
        get() = BuildConfig.DEBUG &&
            !useCloudOverride &&
            System.getProperty("headstart.cloud") == null

    @Volatile
    private var wired = false

    /**
     * Must run once, from [app.headstart.ServiceLocator.init], before any other Firebase
     * call: `useEmulator` throws once a client has already started talking to a backend.
     */
    @Synchronized
    fun wire(auth: FirebaseAuth, db: FirebaseFirestore, fns: FirebaseFunctions) {
        if (wired) return
        wired = true
        val local = useLocalEmulators
        if (local) {
            auth.useEmulator(EMULATOR_HOST, AUTH_PORT)
            // No SafetyNet, no Play Integrity, no reCAPTCHA web view and no SMS: the Auth
            // emulator hands the code out at
            // http://127.0.0.1:9099/emulator/v1/projects/fin-e8358/verificationCodes
            auth.firebaseAuthSettings.setAppVerificationDisabledForTesting(true)
            db.useEmulator(EMULATOR_HOST, FIRESTORE_PORT)
            fns.useEmulator(EMULATOR_HOST, FUNCTIONS_PORT)
        }
        Log.i(LOG_TAG, "Firebase target = " + if (local) "emulator 10.0.2.2" else "cloud")
    }
}
