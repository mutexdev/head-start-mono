package app.headstart.push

/**
 * Every routing decision an incoming push triggers, as pure Kotlin.
 *
 * Deliberately free of `android.*` — this file runs in a JVM unit test, and it is the
 * single code path shared by the real [HeadstartMessagingService] and the debug-variant
 * push injector. If the two ever diverged, the thing the reviewer verifies on the AVD would
 * stop being the thing that ships.
 *
 * CLIENT_CONTRACT.md and addendum §C: `leadTime` is the ONLY urgent kind. `arrived`
 * included, everything else is quiet — a loud channel that fires five times a trip stops
 * meaning anything.
 */

/** IMPORTANCE_HIGH, own sound, bypasses DND where permitted. Only `leadTime`. */
const val CHANNEL_URGENT = "sync_urgent"

/** IMPORTANCE_DEFAULT. Every other kind, plus the ongoing trip notification. */
const val CHANNEL_UPDATES = "sync_updates"

/** The foreground service's ongoing notification. No alert may ever collide with it. */
const val ONGOING_TRIP_ID = 1001

/** Alert ids are ALERT_BASE_ID + the kind's index, so they can never reach ONGOING_TRIP_ID. */
const val ALERT_BASE_ID = 2000

/** The thirteen `data.kind` values from CLIENT_CONTRACT.md, in contract order. */
val PUSH_KINDS: List<String> = listOf(
    "started", "tenMin", "leadTime", "slip", "arrived", "lost", "timeout",
    "cancelled", "didYouLeave", "armed", "noShow", "runningLate", "reply",
)

/** The one urgent kind. Unknown kinds fall back to the quiet channel. */
fun channelFor(kind: String?): String =
    if (kind == "leadTime") CHANNEL_URGENT else CHANNEL_UPDATES

/**
 * One stable id per kind, so a newer "10 min away" replaces the older one rather than
 * stacking. Unknown kinds share one bucket at the end. Never equal to [ONGOING_TRIP_ID].
 */
fun notificationIdFor(kind: String?): Int {
    val index = PUSH_KINDS.indexOf(kind)
    return ALERT_BASE_ID + if (index >= 0) index else PUSH_KINDS.size
}

/** The driver's "did you actually leave?" sheet (DriverNudge.dc.html). */
fun raisesNudgeSheet(kind: String?): Boolean = kind == "didYouLeave"

/**
 * Kinds after which there is nothing left to track. Note `arrived` is the SERVER's
 * decision — the client never invents it, it only reacts to it.
 */
fun endsTracking(kind: String?): Boolean =
    kind == "arrived" || kind == "cancelled" || kind == "timeout"

/**
 * Everything the notification layer needs, derived from an FCM `data` map.
 * Addendum §D: trip-scoped pushes carry `data.tripId`; non-trip pushes omit it.
 */
data class PushRenderSpec(
    val kind: String?,
    val title: String,
    val body: String,
    val tripId: String?,
    val channelId: String,
    val notificationId: Int,
    val urgent: Boolean,
    val raisesNudgeSheet: Boolean,
    val endsTracking: Boolean,
) {
    /** Nothing to put in the tray; the data-only push still drives the side effects. */
    val hasText: Boolean get() = title.isNotEmpty() || body.isNotEmpty()
}

/** The one translation from wire format to render decisions. */
fun renderSpec(data: Map<String, String>): PushRenderSpec {
    val kind = data["kind"]?.takeIf { it.isNotEmpty() }
    val channel = channelFor(kind)
    return PushRenderSpec(
        kind = kind,
        title = data["title"].orEmpty(),
        body = data["body"].orEmpty(),
        tripId = data["tripId"]?.takeIf { it.isNotEmpty() },
        channelId = channel,
        notificationId = notificationIdFor(kind),
        urgent = channel == CHANNEL_URGENT,
        raisesNudgeSheet = raisesNudgeSheet(kind),
        endsTracking = endsTracking(kind),
    )
}
