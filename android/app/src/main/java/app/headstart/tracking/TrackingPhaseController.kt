package app.headstart.tracking

import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * A single OS location fix, stripped of Android types so this file stays pure Kotlin
 * and runs on the JVM. The iOS twin (`TrackingPhaseController.swift`) mirrors it exactly.
 */
data class LocationFix(
    val lat: Double,
    val lng: Double,
    val accuracyM: Double,
    val speedMps: Double,
    val tsMs: Long,
)

enum class Phase { FAR, NEAR }

enum class LocationPriority { BALANCED, HIGH }

data class LocationParams(
    val priority: LocationPriority,
    val minIntervalMs: Long,
    val minDisplacementM: Float,
)

enum class SkipReason { LOW_ACCURACY, STALE_TIMESTAMP, TOO_SOON }

sealed interface FixDecision {
    data class Upload(val fix: LocationFix, val phase: Phase) : FixDecision
    data class Skip(val reason: SkipReason) : FixDecision
}

/** Upload filter condition 1 from CLIENT_CONTRACT.md. */
const val MAX_ACCURACY_M = 100.0

/** Local safety net: stop tracking after three hours no matter what the server says. */
const val TRIP_GUARD_MS = 3L * 60L * 60L * 1000L

const val LOW_BATTERY_PERCENT = 15

fun haversineMeters(aLat: Double, aLng: Double, bLat: Double, bLng: Double): Double {
    val r = 6_371_000.0
    val dLat = Math.toRadians(bLat - aLat)
    val dLng = Math.toRadians(bLng - aLng)
    val s = sin(dLat / 2) * sin(dLat / 2) +
        cos(Math.toRadians(aLat)) * cos(Math.toRadians(bLat)) * sin(dLng / 2) * sin(dLng / 2)
    return 2 * r * asin(min(1.0, sqrt(s)))
}

/**
 * The shared tracking algorithm from CLIENT_CONTRACT.md §"Shared tracking algorithm".
 *
 * Not thread-safe by design: `LocationForegroundService` confines every call to a single
 * coroutine. Keep it free of Android imports — this class must run in a JVM unit test.
 *
 * @param spotLat destination latitude, from `trip.spot.lat`
 * @param spotLng destination longitude, from `trip.spot.lng`
 * @param nearBandM `trip.bands.near`, in metres from the destination
 * @param startedAtMs local clock at trip start, for the three-hour guard
 */
class TrackingPhaseController(
    private val spotLat: Double,
    private val spotLng: Double,
    private val nearBandM: Double,
    private val startedAtMs: Long,
) {
    var phase: Phase = Phase.FAR
        private set

    var lowBattery: Boolean = false
        private set

    /** The last fix that was actually written. Skipped fixes never become the baseline. */
    var lastUploaded: LocationFix? = null
        private set

    /** `trip.phaseHint` from the trip document listener. Only "near" does anything. */
    fun onServerPhaseHint(hint: String?) {
        if (hint == "near") phase = Phase.NEAR
    }

    /**
     * Feed the OS battery level. Returns true exactly once — on the transition into
     * low battery — so the caller knows to send `setLowBattery({lowBattery:true})`.
     * Latches for the rest of the trip (decision D3).
     */
    fun onBatteryPercent(percent: Int): Boolean {
        if (!lowBattery && percent in 0 until LOW_BATTERY_PERCENT) {
            lowBattery = true
            return true
        }
        return false
    }

    /** Location request parameters for the current phase and battery state. */
    fun params(): LocationParams = when {
        // D2: low battery never downgrades the near phase.
        phase == Phase.NEAR -> LocationParams(LocationPriority.HIGH, 5_000L, 10f)
        lowBattery -> LocationParams(LocationPriority.BALANCED, 60_000L, 400f)
        else -> LocationParams(LocationPriority.BALANCED, 30_000L, 200f)
    }

    fun shouldStop(nowMs: Long): Boolean = nowMs - startedAtMs >= TRIP_GUARD_MS

    /**
     * Runs the accuracy gate, then the phase transition, then the interval/displacement
     * filter, and reports what the caller should do with this fix.
     */
    fun onFix(fix: LocationFix): FixDecision {
        // D1: junk fixes are discarded before they can influence anything.
        if (fix.accuracyM > MAX_ACCURACY_M) return FixDecision.Skip(SkipReason.LOW_ACCURACY)

        // Phase transition — one-way, evaluated against this fix (D4).
        if (phase == Phase.FAR &&
            haversineMeters(fix.lat, fix.lng, spotLat, spotLng) <= nearBandM
        ) {
            phase = Phase.NEAR
        }

        val last = lastUploaded
        if (last == null) {
            lastUploaded = fix
            return FixDecision.Upload(fix, phase)
        }
        if (fix.tsMs <= last.tsMs) return FixDecision.Skip(SkipReason.STALE_TIMESTAMP)

        val p = params()
        val elapsedMs = fix.tsMs - last.tsMs
        val movedM = haversineMeters(fix.lat, fix.lng, last.lat, last.lng)
        return if (elapsedMs >= p.minIntervalMs || movedM >= p.minDisplacementM) {
            lastUploaded = fix
            FixDecision.Upload(fix, phase)
        } else {
            FixDecision.Skip(SkipReason.TOO_SOON)
        }
    }
}
