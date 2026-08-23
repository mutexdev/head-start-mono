package app.headstart.data

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * The only document shape clients are allowed to write (CLIENT_CONTRACT.md
 * §"The one thing clients write"). `expireAt` is added by the sink.
 */
data class PositionUpload(
    val lat: Double,
    val lng: Double,
    val accuracyM: Double,
    val speedMps: Double,
    /** epoch milliseconds */
    val ts: Long,
    /**
     * Android leaves this null: the server does the routing call (addendum §F).
     * The field exists only so the sink stays symmetric with the iOS twin, which
     * fills it from MapKit. No Android code may set it.
     */
    val etaSec: Int? = null,
)

interface PositionSink {
    /** Writes one position. Must throw on failure so the uploader can keep it buffered. */
    suspend fun write(tripId: String, position: PositionUpload)
}

/**
 * Owns the offline buffer. Fixes are appended in order, the oldest are dropped once the
 * cap is reached, and every flush replays oldest-first and stops at the first failure so
 * the remaining order is preserved.
 */
class PositionUploader(
    private val tripId: String,
    private val sink: PositionSink,
    private val maxBuffer: Int = 500,
) {
    private val buffer = ArrayDeque<PositionUpload>()
    private val mutex = Mutex()

    val pending: Int get() = buffer.size

    /** How many fixes the cap has thrown away this trip — surfaced in the debug log only. */
    var dropped: Int = 0
        private set

    /** Buffers the fix and immediately tries to drain. Returns how many were written. */
    suspend fun submit(position: PositionUpload): Int = mutex.withLock {
        buffer.addLast(position)
        while (buffer.size > maxBuffer) {
            buffer.removeFirst()
            dropped++
        }
        drain()
    }

    /** Retries the backlog. Returns how many were written. */
    suspend fun flush(): Int = mutex.withLock { drain() }

    private suspend fun drain(): Int {
        var sent = 0
        while (buffer.isNotEmpty()) {
            val head = buffer.first()
            try {
                sink.write(tripId, head)
            } catch (t: Throwable) {
                break // stay buffered, keep the order, try again on the next fix
            }
            buffer.removeFirst()
            sent++
        }
        return sent
    }
}
