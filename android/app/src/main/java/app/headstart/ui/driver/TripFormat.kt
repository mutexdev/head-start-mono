package app.headstart.ui.driver

import app.headstart.core.arrivalClock
import app.headstart.core.clockAt
import app.headstart.core.minutesAway
import app.headstart.data.Trip
import java.time.ZoneId

/**
 * "What {receiver} has been told" — the middle of DriverTrip.dc.html — plus the two lines
 * above it. All of it is arithmetic over the trip document, so all of it is pure and
 * tested; the screen files carry no logic of their own.
 *
 * Every minute figure comes from [minutesAway] (core/Format.kt), which is the same
 * rounding the server uses in its push copy. The number on screen and the number in the
 * notification are therefore the same number, never off by one.
 */
enum class StepState {
    /** The receiver has already been told. */
    DONE,

    /** Not yet — an ordinary rung. */
    PENDING,

    /** Not yet — the walk-out rung, drawn in Headstart amber. */
    PENDING_LEAD,
}

data class LadderStep(
    val label: String,
    /** Extra text appended in amber on the lead rung, e.g. "3 min". */
    val detail: String?,
    /** "5:26 pm" once fired, "in 8 min" while pending, "" when the ETA is unknown. */
    val timing: String,
    val state: StepState,
)

/**
 * The three rungs of the alert ladder, always three, always in order.
 *
 * [nowMs] is part of the signature because the screen re-renders on a ticker and a future
 * rung's copy is time-relative; the current rules read only the trip, so it is unused
 * today. Keeping it means the call sites do not change when they need it.
 */
@Suppress("UNUSED_PARAMETER")
fun ladderFor(
    trip: Trip,
    nowMs: Long,
    zone: ZoneId = ZoneId.systemDefault(),
): List<LadderStep> {
    val etaSec = trip.eta?.seconds

    // A rung that has not fired shows how long until it will. Below half a minute it
    // says so in words rather than counting "in 0 min", and with no ETA it says nothing
    // at all — an invented countdown here would be a lie about what the receiver knows.
    fun pendingTiming(secondsUntilFire: Int?): String = when {
        secondsUntilFire == null -> ""
        secondsUntilFire <= 30 -> "any moment"
        else -> "in ${minutesAway(secondsUntilFire)} min"
    }

    val started = LadderStep(
        label = "You started driving",
        detail = null,
        timing = trip.startedAtMs?.let { clockAt(it, zone) } ?: "",
        state = if (trip.alerts.started) StepState.DONE else StepState.PENDING,
    )

    val tenMin = if (trip.alerts.tenMin) {
        LadderStep("10 minutes away", null, "sent", StepState.DONE)
    } else {
        LadderStep("10 minutes away", null, pendingTiming(etaSec?.minus(600)), StepState.PENDING)
    }

    val leadSeconds = trip.leadTimeMin * 60
    val lead = if (trip.alerts.leadTime) {
        LadderStep("Start walking now", "${trip.leadTimeMin} min", "sent", StepState.DONE)
    } else {
        LadderStep(
            label = "Start walking now",
            detail = "${trip.leadTimeMin} min",
            timing = pendingTiming(etaSec?.minus(leadSeconds)),
            state = StepState.PENDING_LEAD,
        )
    }

    return listOf(started, tenMin, lead)
}

/** The 88 sp number on DriverTrip. An em dash, never a zero, while the ETA is unknown. */
fun driverEtaMinutes(trip: Trip): String =
    trip.eta?.let { minutesAway(it.seconds).toString() } ?: "—"

/** "Arriving at Office around 5:48 pm". */
fun driverArrivalLine(trip: Trip, nowMs: Long, zone: ZoneId = ZoneId.systemDefault()): String {
    val eta = trip.eta ?: return "Working out the route to ${trip.spotName}"
    val suffix = if (eta.approximate) " (approx.)" else ""
    return "Arriving at ${trip.spotName} around ${arrivalClock(nowMs, eta.seconds, zone)}$suffix"
}
