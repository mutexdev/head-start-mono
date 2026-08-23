package app.headstart.data

import app.headstart.core.Callables
import app.headstart.core.HeadstartError
import app.headstart.core.snapshotFlow
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Query
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.map
import java.util.concurrent.ConcurrentHashMap

data class StartTripResult(
    val tripId: String,
    val bands: Bands,
    val etaSeconds: Int,
    /**
     * True when a trip was already running for this pair; the server returned that one.
     * Addendum §E: attach to it — do NOT restart tracking or replay first-start UI.
     */
    val existing: Boolean,
)

@Suppress("UNCHECKED_CAST")
fun startTripResultFrom(raw: Map<String, Any?>?): StartTripResult? {
    val d = raw ?: return null
    val tripId = d["tripId"] as? String ?: return null
    val bandsMap = d["bands"] as? Map<String, Any?> ?: return null
    val far = (bandsMap["far"] as? Number)?.toDouble() ?: return null
    val near = (bandsMap["near"] as? Number)?.toDouble() ?: return null
    val lead = (bandsMap["lead"] as? Number)?.toDouble() ?: return null
    return StartTripResult(
        tripId = tripId,
        bands = Bands(far, near, lead),
        etaSeconds = (d["etaSeconds"] as? Number)?.toInt() ?: 0,
        existing = d["existing"] as? Boolean ?: false,
    )
}

/** `setRunningLate` accepts 1–60 extra minutes (addendum §K). */
fun clampExtraMin(value: Int): Int = value.coerceIn(1, 60)

/** The four kinds `sendReply` accepts (addendum §B). `runningLate` is NOT one of them. */
val REPLY_KINDS: List<String> = listOf("fiveMore", "takeYourTime", "atSpot", "custom")

class TripRepository(
    private val db: FirebaseFirestore,
    private val callables: Callables,
) {
    /**
     * Addendum §L: the low-battery latch is per-trip, keyed by tripId, and lives here.
     * Set once on the first OS report under 15 %, never cleared for that trip.
     */
    private val lowBatteryLatched: MutableSet<String> = ConcurrentHashMap.newKeySet()

    /**
     * The pair's live trip. `pairId == x AND state in [armed, driving]` is the query
     * CLIENT_CONTRACT.md specifies, served by the (pairId, state) composite index the
     * backend declares. Against the real cloud a missing index surfaces as
     * HeadstartError.Unknown carrying the create-index URL.
     *
     * FALLBACK, and why it exists. Firestore evaluates rules for a `list` against the
     * QUERY, not against the documents it would return: any field the rule reads must be
     * constrained by the query. `firestore.rules` currently guards trips with
     * `uid() == resource.data.driverUid || uid() == resource.data.receiverUid`, and the
     * contract query constrains neither field, so the emulator answers the contract's own
     * query with
     *
     *   PERMISSION_DENIED: Property driverUid is undefined on object. for 'list' @ L37
     *
     * Reproduced outside the app with a real ID token, so it is not a client bug and it
     * will behave the same in production. The backend fix is one line — guard trips the way
     * spots are guarded, `allow read: if isMember(resource.data.pairId)` — after which the
     * contract query below succeeds and this fallback never runs again.
     *
     * Until then we fall back to two uid-constrained listeners, which the existing rule DOES
     * admit and which need no new index (single-field equality is auto-indexed); `state` and
     * `pairId` are filtered in Kotlin. It is strictly narrower than the contract query — it
     * can only ever return a trip this user is a member of.
     */
    fun activeTrip(pairId: String, myUid: String?): Flow<Trip?> =
        db.collection("trips")
            .whereEqualTo("pairId", pairId)
            .whereIn("state", listOf("armed", "driving"))
            .snapshotFlow()
            .map { snap -> snap.documents.firstNotNullOfOrNull { tripFrom(it.id, it.data) } }
            .catch { error ->
                if (myUid == null || !error.isPermissionDenied()) throw error
                emitAll(activeTripByMembership(pairId, myUid))
            }

    private fun activeTripByMembership(pairId: String, myUid: String): Flow<Trip?> {
        fun side(field: String): Flow<List<Trip>> =
            db.collection("trips")
                .whereEqualTo(field, myUid)
                .snapshotFlow()
                .map { snap -> snap.documents.mapNotNull { tripFrom(it.id, it.data) } }

        return combine(side("driverUid"), side("receiverUid")) { asDriver, asReceiver ->
            (asDriver + asReceiver).firstOrNull {
                it.pairId == pairId && (it.isDriving || it.isArmed)
            }
        }
    }

    /** One specific trip — used by the foreground service, which knows its own trip id. */
    fun trip(tripId: String): Flow<Trip?> =
        db.collection("trips").document(tripId).snapshotFlow()
            .map { snap -> snap?.let { tripFrom(it.id, it.data) } }

    fun replies(tripId: String): Flow<List<Reply>> =
        db.collection("trips").document(tripId).collection("replies")
            .orderBy("ts", Query.Direction.ASCENDING)
            .snapshotFlow()
            .map { snap -> snap.documents.mapNotNull { replyFrom(it.id, it.data) } }

    /**
     * Android drivers never send `etaSec` — the server makes the Routes API call
     * (addendum §F). The parameter exists only so the two platforms share one contract
     * shape; iOS fills it from MapKit.
     */
    suspend fun startTrip(
        spotId: String,
        lat: Double,
        lng: Double,
        fuzzy: Boolean,
        etaSec: Int? = null,
    ): StartTripResult {
        val payload = mutableMapOf<String, Any?>(
            "spotId" to spotId,
            "lat" to lat,
            "lng" to lng,
            "fuzzy" to fuzzy,
        )
        if (etaSec != null) payload["etaSec"] = etaSec
        val res = callables.call("startTrip", payload)
        return startTripResultFrom(res) ?: throw HeadstartError.Unknown("startTrip-bad-response")
    }

    /** Receiver-initiated "ping me when they leave". `neededBy` rides on armTrip (addendum §A). */
    suspend fun armTrip(spotId: String, neededByMs: Long? = null): String {
        val payload = mutableMapOf<String, Any?>("spotId" to spotId)
        if (neededByMs != null) payload["neededBy"] = neededByMs
        val res = callables.call("armTrip", payload)
        return res["tripId"] as? String ?: throw HeadstartError.Unknown("armTrip-no-id")
    }

    suspend fun endTrip(tripId: String, reason: String) {
        require(reason == "arrived" || reason == "cancelled") { "reason must be arrived or cancelled" }
        callables.call("endTrip", mapOf("tripId" to tripId, "reason" to reason))
    }

    suspend fun sendReply(tripId: String, kind: String, text: String? = null) {
        require(kind in REPLY_KINDS) { "kind must be one of $REPLY_KINDS" }
        if (kind == "custom" && text.isNullOrBlank()) throw HeadstartError.BadReply
        val payload = mutableMapOf<String, Any?>("tripId" to tripId, "kind" to kind)
        if (text != null) payload["text"] = text
        callables.call("sendReply", payload)
    }

    suspend fun setRunningLate(tripId: String, extraMin: Int) {
        callables.call("setRunningLate", mapOf("tripId" to tripId, "extraMin" to clampExtraMin(extraMin)))
    }

    /**
     * Latched per trip. Returns true when the callable was actually made, false when this
     * trip already reported low battery — the caller (the foreground service) may treat a
     * false as "nothing to do".
     */
    suspend fun setLowBattery(tripId: String, lowBattery: Boolean = true): Boolean {
        if (lowBattery && !lowBatteryLatched.add(tripId)) return false
        callables.call("setLowBattery", mapOf("lowBattery" to lowBattery))
        return true
    }
}

private fun Throwable.isPermissionDenied(): Boolean =
    (this as? FirebaseFirestoreException)?.code ==
        FirebaseFirestoreException.Code.PERMISSION_DENIED
