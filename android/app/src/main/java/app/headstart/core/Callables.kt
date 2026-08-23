package app.headstart.core

import com.google.firebase.functions.FirebaseFunctions
import kotlinx.coroutines.tasks.await

/**
 * One place that calls Cloud Functions. Every failure leaves here as a [HeadstartError].
 * Callable names and payloads are fixed by docs/CLIENT_CONTRACT.md and its addendum §A:
 * registerPushToken, createPair, acceptPair, revokePair, upsertSpot, deleteSpot,
 * startTrip, armTrip, endTrip, sendReply, setRunningLate, setLowBattery — and nothing else.
 */
class Callables(private val functions: FirebaseFunctions) {

    suspend fun call(name: String, data: Map<String, Any?> = emptyMap()): Map<String, Any?> {
        try {
            val result = functions.getHttpsCallable(name).call(data).await()
            @Suppress("UNCHECKED_CAST")
            return (result.data as? Map<String, Any?>) ?: emptyMap()
        } catch (t: Throwable) {
            throw t.toHeadstartError()
        }
    }
}

// Callable responses arrive as Integer/Double/String/Boolean boxes — read them defensively.
fun Map<String, Any?>.str(key: String): String? = this[key] as? String
fun Map<String, Any?>.int(key: String): Int? = (this[key] as? Number)?.toInt()
fun Map<String, Any?>.long(key: String): Long? = (this[key] as? Number)?.toLong()
fun Map<String, Any?>.dbl(key: String): Double? = (this[key] as? Number)?.toDouble()
fun Map<String, Any?>.bool(key: String): Boolean? = this[key] as? Boolean

@Suppress("UNCHECKED_CAST")
fun Map<String, Any?>.map(key: String): Map<String, Any?>? = this[key] as? Map<String, Any?>
