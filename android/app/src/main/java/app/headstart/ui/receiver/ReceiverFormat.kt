package app.headstart.ui.receiver

import app.headstart.core.minutesAway
import kotlin.math.max

/**
 * The receiver's countdown, as pure arithmetic.
 *
 * Everything here is driven by `trip.receiverView`, which is the only thing the server
 * lets a receiver see (contract §"Firestore reads", addendum §H). There is deliberately no
 * function in this file that takes a position.
 */

/**
 * Seconds until the receiver should stand up, counted from the last `receiverView` the
 * server sent and ticked forward locally. Clamped at zero: an overdue countdown becomes
 * "walk out now", never a negative number.
 */
fun headstartSecondsLeft(etaSeconds: Int, leadTimeMin: Int, elapsedSinceUpdateSec: Int): Int =
    max(0, etaSeconds - leadTimeMin * 60 - elapsedSinceUpdateSec)

fun isWalkOutNow(secondsLeft: Int): Boolean = secondsLeft <= 0

/** "10 min away" — same rounding as the push, so the two never disagree. */
fun receiverStatusLine(etaSeconds: Int): String = "${minutesAway(etaSeconds)} min away"

fun clampProgressPct(value: Int): Int = value.coerceIn(0, 100)
