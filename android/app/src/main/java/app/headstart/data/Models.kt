package app.headstart.data

// ---------- documents ----------

const val PARTNER_NAME_FALLBACK = "Your partner"

data class PairInfo(
    val id: String,
    val members: List<String>,
    val status: String,
    val inviteCode: String,
    val createdBy: String,
    val createdAtMs: Long?,
    /**
     * `uid -> displayName`, denormalised onto the pair by the backend so neither side has
     * to read the other's user document (contract §"Firestore reads", addendum §M).
     */
    val memberNames: Map<String, String> = emptyMap(),
) {
    val isActive: Boolean get() = status == "active"

    /**
     * Only a "pending" pair can still be accepted. `!isActive` is NOT a synonym:
     * it also matches "revoked", and offering a revoked code as a fresh invite
     * hands the other person a code acceptPair is guaranteed to reject.
     */
    val isPending: Boolean get() = status == "pending"
    fun otherUid(myUid: String): String? = members.firstOrNull { it != myUid }

    /**
     * The other person's name, the one and only way this app resolves it. Falls back to
     * "Your partner" while `memberNames` is missing the key — which is the state right
     * after `createPair` and before the other side has set a display name.
     */
    fun partnerName(myUid: String): String {
        val other = otherUid(myUid) ?: return PARTNER_NAME_FALLBACK
        return memberNames[other]?.takeIf { it.isNotBlank() } ?: PARTNER_NAME_FALLBACK
    }
}

data class Spot(
    val id: String,
    val pairId: String,
    val name: String,
    val lat: Double,
    val lng: Double,
    val radiusM: Int,
    val leadTimeMin: Int,
    val createdBy: String,
)

data class Bands(val far: Double, val near: Double, val lead: Double)

data class Eta(val seconds: Int, val updatedAtMs: Long, val approximate: Boolean)

/**
 * What a receiver is allowed to see. Addendum §H: the driver's position must never reach a
 * receiver surface, and that is enforced structurally — this class has no position field
 * at all, and [tripFrom] never reads `receiverView.lastPos` or the trip's top-level
 * `lastPos`. There is nothing for a screen to render even by mistake.
 */
data class ReceiverView(
    val etaSeconds: Int,
    val progressPct: Int,
)

data class TripAlerts(
    val started: Boolean = false,
    val tenMin: Boolean = false,
    val leadTime: Boolean = false,
    val arrived: Boolean = false,
    val didYouLeave: Boolean = false,
    val slipCount: Int = 0,
)

data class Trip(
    val id: String,
    val pairId: String,
    val driverUid: String,
    val receiverUid: String,
    val spotId: String,
    val spotName: String,
    val spotLat: Double,
    val spotLng: Double,
    val spotRadiusM: Int,
    val leadTimeMin: Int,
    val state: String,
    val startedAtMs: Long?,
    val eta: Eta?,
    val bands: Bands?,
    val phaseHint: String,
    val receiverView: ReceiverView?,
    val alerts: TripAlerts,
    val routePolyline: String?,
) {
    val isDriving: Boolean get() = state == "driving"
    val isArmed: Boolean get() = state == "armed"
    fun isDriver(uid: String?): Boolean = uid != null && uid == driverUid
    fun isReceiver(uid: String?): Boolean = uid != null && uid == receiverUid
}

data class Reply(
    val id: String,
    val fromUid: String,
    val kind: String,
    val text: String?,
    val tsMs: Long,
) {
    val displayText: String
        get() = when (kind) {
            "fiveMore" -> "5 more minutes please"
            "takeYourTime" -> "Take your time"
            "atSpot" -> "I'm at the spot"
            // Not a client reply kind (addendum §B) — but the server may record one here.
            "runningLate" -> "Running late"
            else -> text.orEmpty()
        }
}

// ---------- pure mappers ----------

private fun Map<String, Any?>.s(key: String): String? = this[key] as? String
private fun Map<String, Any?>.i(key: String): Int? = (this[key] as? Number)?.toInt()
private fun Map<String, Any?>.l(key: String): Long? = (this[key] as? Number)?.toLong()
private fun Map<String, Any?>.d(key: String): Double? = (this[key] as? Number)?.toDouble()
private fun Map<String, Any?>.b(key: String): Boolean = this[key] as? Boolean ?: false

@Suppress("UNCHECKED_CAST")
private fun Map<String, Any?>.m(key: String): Map<String, Any?>? = this[key] as? Map<String, Any?>

private fun Map<String, Any?>.stringMap(key: String): Map<String, String> =
    m(key)?.mapNotNull { (k, v) -> (v as? String)?.let { k to it } }?.toMap() ?: emptyMap()

private fun Map<String, Any?>.strings(key: String): List<String>? =
    (this[key] as? List<*>)?.mapNotNull { it as? String }

fun pairFrom(id: String, data: Map<String, Any?>?): PairInfo? {
    val d = data ?: return null
    val members = d.strings("members") ?: return null
    if (members.isEmpty()) return null
    return PairInfo(
        id = id,
        members = members,
        status = d.s("status") ?: "pending",
        inviteCode = d.s("inviteCode").orEmpty(),
        createdBy = d.s("createdBy").orEmpty(),
        createdAtMs = d.l("createdAt"),
        memberNames = d.stringMap("memberNames"),
    )
}

fun spotFrom(id: String, data: Map<String, Any?>?): Spot? {
    val d = data ?: return null
    val name = d.s("name") ?: return null
    val lat = d.d("lat") ?: return null
    val lng = d.d("lng") ?: return null
    return Spot(
        id = id,
        pairId = d.s("pairId").orEmpty(),
        name = name,
        lat = lat,
        lng = lng,
        radiusM = d.i("radiusM") ?: 100,
        leadTimeMin = d.i("leadTimeMin") ?: 3,
        createdBy = d.s("createdBy").orEmpty(),
    )
}

fun tripFrom(id: String, data: Map<String, Any?>?): Trip? {
    val d = data ?: return null
    val driverUid = d.s("driverUid") ?: return null
    val receiverUid = d.s("receiverUid") ?: return null
    val state = d.s("state") ?: return null
    val spot = d.m("spot") ?: return null
    val spotLat = spot.d("lat") ?: return null
    val spotLng = spot.d("lng") ?: return null

    val eta = d.m("eta")?.let {
        val seconds = it.i("seconds") ?: return@let null
        Eta(seconds, it.l("updatedAt") ?: 0L, it.b("approximate"))
    }
    val bands = d.m("bands")?.let {
        Bands(it.d("far") ?: 0.0, it.d("near") ?: 0.0, it.d("lead") ?: 0.0)
    }
    // Addendum §H: `lastPos` — wherever it appears in the document — is deliberately not read.
    val receiverView = d.m("receiverView")?.let { rv ->
        ReceiverView(
            etaSeconds = rv.i("etaSeconds") ?: 0,
            progressPct = rv.i("progressPct") ?: 0,
        )
    }
    // Addendum §I: any alert flag may be absent until it first fires — never trap.
    val alerts = d.m("alerts")?.let {
        TripAlerts(
            started = it.b("started"),
            tenMin = it.b("tenMin"),
            leadTime = it.b("leadTime"),
            arrived = it.b("arrived"),
            didYouLeave = it.b("didYouLeave"),
            slipCount = it.i("slipCount") ?: 0,
        )
    } ?: TripAlerts()

    return Trip(
        id = id,
        pairId = d.s("pairId").orEmpty(),
        driverUid = driverUid,
        receiverUid = receiverUid,
        spotId = d.s("spotId").orEmpty(),
        spotName = spot.s("name").orEmpty(),
        spotLat = spotLat,
        spotLng = spotLng,
        spotRadiusM = spot.i("radiusM") ?: 100,
        leadTimeMin = d.i("leadTimeMin") ?: 3,
        state = state,
        startedAtMs = d.l("startedAt"),
        eta = eta,
        bands = bands,
        phaseHint = d.s("phaseHint") ?: "far",
        receiverView = receiverView,
        alerts = alerts,
        routePolyline = d.s("routePolyline"),
    )
}

fun replyFrom(id: String, data: Map<String, Any?>?): Reply? {
    val d = data ?: return null
    val fromUid = d.s("fromUid") ?: return null
    return Reply(
        id = id,
        fromUid = fromUid,
        kind = d.s("kind") ?: "custom",
        text = d.s("text"),
        tsMs = d.l("ts") ?: 0L,
    )
}
