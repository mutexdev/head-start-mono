package app.headstart.core

import com.google.firebase.functions.FirebaseFunctionsException
import java.io.IOException

/**
 * Every failure the UI has to explain. [code] is the wire value from CLIENT_CONTRACT.md;
 * [userMessage] is what a screen may put in front of a person.
 */
sealed class HeadstartError(
    val code: String,
    val userMessage: String,
) : Exception(code) {
    object NotPaired : HeadstartError("not-paired", "You're not paired with anyone yet.")
    object TripActive : HeadstartError("trip-active", "A trip is already running.")
    object SpotNotFound : HeadstartError("spot-not-found", "That pickup spot no longer exists.")
    object BadCode : HeadstartError("bad-code", "That code isn't valid. Check the six characters and try again.")
    object OwnCode : HeadstartError("own-code", "That's your own invite code. Send it to the other person.")
    object DriverOnly : HeadstartError("driver-only", "Only the driver can do that.")
    object TripNotFound : HeadstartError("trip-not-found", "That trip has already ended.")
    object BadCoords : HeadstartError("bad-coords", "We couldn't read that location. Try again.")
    object BadName : HeadstartError("bad-name", "Give the spot a name of 1 to 40 characters.")
    object BadToken : HeadstartError("bad-token", "Notifications aren't set up on this phone yet.")

    /** Addendum §O: returned by `sendReply` when custom text is empty. */
    object BadReply : HeadstartError("bad-reply", "Type something before you send it.")

    object Unauthenticated : HeadstartError("unauthenticated", "Sign in again to continue.")
    object Offline : HeadstartError("offline", "No connection. We'll try again when you're back online.")

    // Client-side only: raised by AuthRepository, never returned by a callable.
    object InvalidPhone : HeadstartError("invalid-phone", "That doesn't look like a phone number we can text.")
    object InvalidSmsCode : HeadstartError("invalid-sms-code", "That code doesn't match. Check the six digits.")
    object SmsQuotaExceeded : HeadstartError("sms-quota", "Too many attempts. Wait a few minutes and try again.")
    object SessionExpired : HeadstartError("session-expired", "That code expired. Ask for a new one.")

    class Unknown(rawCode: String) : HeadstartError(rawCode, "Something went wrong. Try again.")
}

private val BY_CODE: List<HeadstartError> = listOf(
    HeadstartError.NotPaired,
    HeadstartError.TripActive,
    HeadstartError.SpotNotFound,
    HeadstartError.BadCode,
    HeadstartError.OwnCode,
    HeadstartError.DriverOnly,
    HeadstartError.TripNotFound,
    HeadstartError.BadCoords,
    HeadstartError.BadName,
    HeadstartError.BadToken,
    HeadstartError.BadReply,
)

/**
 * Pure mapper: callable message (plus two transport facts) to a typed error.
 * Auth and connectivity outrank the message, because a stale token can produce any message.
 */
fun headstartErrorFor(
    message: String?,
    isNetwork: Boolean = false,
    isUnauthenticated: Boolean = false,
): HeadstartError {
    if (isUnauthenticated) return HeadstartError.Unauthenticated
    if (isNetwork) return HeadstartError.Offline
    val text = message?.trim().orEmpty()
    if (text.isEmpty()) return HeadstartError.Unknown("unknown")
    BY_CODE.firstOrNull { it.code == text }?.let { return it }
    // Some transports prefix the status, e.g. "INVALID_ARGUMENT: bad-code".
    BY_CODE.firstOrNull { text.contains(it.code) }?.let { return it }
    return HeadstartError.Unknown(text)
}

/** Adapter from whatever the Firebase SDK threw. */
fun Throwable.toHeadstartError(): HeadstartError {
    if (this is HeadstartError) return this
    val fx = this as? FirebaseFunctionsException
    val isUnauthenticated = fx?.code == FirebaseFunctionsException.Code.UNAUTHENTICATED
    val isNetwork = this is IOException ||
        cause is IOException ||
        fx?.code == FirebaseFunctionsException.Code.UNAVAILABLE ||
        fx?.code == FirebaseFunctionsException.Code.DEADLINE_EXCEEDED
    return headstartErrorFor(message, isNetwork = isNetwork, isUnauthenticated = isUnauthenticated)
}
