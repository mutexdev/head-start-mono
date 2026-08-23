package app.headstart

import android.content.Context
import android.content.SharedPreferences

/**
 * Small, synchronous, boring. Nothing here is worth a DataStore migration in M1.
 *
 * NOTE: `enum class Role` lives in `Role.kt`, not here — the plan doc declares it inside
 * this file, but `RoleSwitch` needs it without dragging in `android.content.Context`.
 */
class Prefs(context: Context) {
    private val sp: SharedPreferences =
        context.getSharedPreferences("headstart", Context.MODE_PRIVATE)

    var role: Role
        get() = if (sp.getString(KEY_ROLE, Role.DRIVING.name) == Role.WAITING.name) Role.WAITING else Role.DRIVING
        set(value) = sp.edit().putString(KEY_ROLE, value.name).apply()

    /** Cached so the tracking service can start before the pair listener has fired. */
    var pairId: String?
        get() = sp.getString(KEY_PAIR_ID, null)
        set(value) = sp.edit().putString(KEY_PAIR_ID, value).apply()

    /**
     * MY OWN name, the one typed on ProfileScreen. Needed before a pair exists, because
     * `registerPushToken` carries it and that is how the server fills
     * `pairs/{pairId}.memberNames`.
     *
     * It is deliberately NOT a partner name. The partner's name has exactly one source in
     * this app — `PairInfo.partnerName(myUid)`, read from `memberNames` (addendum §M) — and
     * nothing may shadow it, or Settings and the spot screens would disagree.
     */
    var displayName: String?
        get() = sp.getString(KEY_DISPLAY_NAME, null)
        set(value) = sp.edit().putString(KEY_DISPLAY_NAME, value).apply()

    var oemNoticeShown: Boolean
        get() = sp.getBoolean(KEY_OEM_NOTICE, false)
        set(value) = sp.edit().putBoolean(KEY_OEM_NOTICE, value).apply()

    /** `fuzzy` on startTrip. Mirrors the Settings toggle "Hide my exact position". */
    var hideExactPosition: Boolean
        get() = sp.getBoolean(KEY_HIDE_POSITION, false)
        set(value) = sp.edit().putBoolean(KEY_HIDE_POSITION, value).apply()

    /** Set once the FCM token has been accepted by registerPushToken for this uid. */
    var registeredTokenUid: String?
        get() = sp.getString(KEY_TOKEN_UID, null)
        set(value) = sp.edit().putString(KEY_TOKEN_UID, value).apply()

    /**
     * The trip the foreground service is currently tracking, so [GeofenceReceiver] — which
     * is woken by the OS with no state of its own — knows which trip to push a fix into.
     * Written when the service starts, cleared the moment it stops.
     */
    var activeTripId: String?
        get() = sp.getString(KEY_ACTIVE_TRIP, null)
        set(value) = sp.edit().putString(KEY_ACTIVE_TRIP, value).apply()

    /**
     * Debug-only escape hatch: point this build at the real cloud instead of the local
     * emulator suite. Read once by [ServiceLocator.init] into
     * [app.headstart.core.HeadstartConfig.useCloudOverride]; takes effect on next launch.
     *
     * Stored in `/data/data/app.headstart/shared_prefs/headstart.xml` under the key
     * `headstart_use_cloud`, so a reviewer can flip it from the host with
     * `adb shell run-as app.headstart ...` (debug builds are debuggable) and relaunch,
     * or use the debug Settings row. It is read once, at process start.
     */
    var useCloud: Boolean
        get() = sp.getBoolean(KEY_USE_CLOUD, false)
        set(value) = sp.edit().putBoolean(KEY_USE_CLOUD, value).apply()

    fun clearAccountScoped() {
        sp.edit()
            .remove(KEY_PAIR_ID)
            .remove(KEY_TOKEN_UID)
            .remove(KEY_DISPLAY_NAME)
            .remove(KEY_ACTIVE_TRIP)
            .apply()
    }

    private companion object {
        const val KEY_ROLE = "role"
        const val KEY_PAIR_ID = "pairId"
        const val KEY_DISPLAY_NAME = "displayName"
        const val KEY_OEM_NOTICE = "oemNoticeShown"
        const val KEY_HIDE_POSITION = "hideExactPosition"
        const val KEY_TOKEN_UID = "registeredTokenUid"
        const val KEY_ACTIVE_TRIP = "activeTripId"
        const val KEY_USE_CLOUD = "headstart_use_cloud"
    }
}
