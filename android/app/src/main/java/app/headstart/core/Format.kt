package app.headstart.core

import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Minutes shown on screen. Identical to the server's `min()` in functions/src/messages.ts
 * so the number in the push and the number in the app never disagree (decision D5).
 */
fun minutesAway(etaSec: Int): Int = max(1, (etaSec / 60.0).roundToInt())

/** "7:20" — never negative, always two-digit seconds. */
fun formatCountdown(totalSec: Int): String {
    val s = max(0, totalSec)
    return String.format(Locale.US, "%d:%02d", s / 60, s % 60)
}

private val CLOCK: DateTimeFormatter = DateTimeFormatter.ofPattern("h:mm a", Locale.US)

/** "5:48 pm" for a wall-clock instant. */
fun clockAt(epochMs: Long, zone: ZoneId = ZoneId.systemDefault()): String =
    Instant.ofEpochMilli(epochMs).atZone(zone).format(CLOCK).lowercase(Locale.US)

/** "5:48 pm" for now + eta. */
fun arrivalClock(nowMs: Long, etaSec: Int, zone: ZoneId = ZoneId.systemDefault()): String =
    clockAt(nowMs + etaSec * 1_000L, zone)

/** "Tuesday evening" — the DriverHome.dc.html eyebrow. */
fun greetingFor(dt: LocalDateTime): String {
    val day = dt.dayOfWeek.getDisplayName(TextStyle.FULL, Locale.US)
    val part = when (dt.hour) {
        in 5..11 -> "morning"
        in 12..16 -> "afternoon"
        in 17..21 -> "evening"
        else -> "night"
    }
    return "$day $part"
}

/** "740 m" / "2.9 km" — the ReceiverTrip subtitle. */
fun formatDistance(metres: Double): String =
    if (metres < 1_000.0) "${metres.roundToInt()} m"
    else String.format(Locale.US, "%.1f km", metres / 1_000.0)
