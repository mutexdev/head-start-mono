package app.headstart.data

import app.headstart.core.Callables
import app.headstart.core.HeadstartError
import app.headstart.core.snapshotFlow
import app.headstart.core.str
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** Mirrors the clamps in `upsertSpot` (addendum §K) so the UI can never propose a rejected value. */
object SpotLimits {
    const val MIN_LEAD_MIN = 1
    const val MAX_LEAD_MIN = 30
    const val DEFAULT_LEAD_MIN = 3

    /** SpotEdit.dc.html shows a 1–15 slider; the contract allows up to 30. */
    const val SLIDER_MAX_LEAD_MIN = 15

    const val MIN_RADIUS_M = 50
    const val MAX_RADIUS_M = 500
    const val DEFAULT_RADIUS_M = 100
    const val MAX_NAME_LENGTH = 40

    val RADIUS_PRESETS = listOf(50, 100, 200, 300, 500)

    fun clampLeadTimeMin(value: Int): Int = value.coerceIn(MIN_LEAD_MIN, MAX_LEAD_MIN)

    fun clampRadiusM(value: Int): Int = value.coerceIn(MIN_RADIUS_M, MAX_RADIUS_M)

    fun nextRadius(current: Int): Int {
        val at = RADIUS_PRESETS.indexOf(current)
        return if (at < 0) RADIUS_PRESETS.first() else RADIUS_PRESETS[(at + 1) % RADIUS_PRESETS.size]
    }

    fun validName(raw: String): String? {
        val trimmed = raw.trim()
        return if (trimmed.isEmpty() || trimmed.length > MAX_NAME_LENGTH) null else trimmed
    }

    fun validCoords(lat: Double, lng: Double): Boolean =
        !lat.isNaN() && !lng.isNaN() && lat in -90.0..90.0 && lng in -180.0..180.0
}

class SpotRepository(
    private val db: FirebaseFirestore,
    private val callables: Callables,
) {
    /** Live list for the pair. Single-field equality — no composite index needed. */
    fun spots(pairId: String): Flow<List<Spot>> =
        db.collection("spots")
            .whereEqualTo("pairId", pairId)
            .snapshotFlow()
            .map { snap ->
                snap.documents.mapNotNull { spotFrom(it.id, it.data) }.sortedBy { it.name.lowercase() }
            }

    /** Creates when [spotId] is null, updates otherwise. Returns the spot id. */
    suspend fun upsertSpot(
        pairId: String,
        name: String,
        lat: Double,
        lng: Double,
        leadTimeMin: Int,
        radiusM: Int,
        spotId: String? = null,
    ): String {
        val cleanName = SpotLimits.validName(name) ?: throw HeadstartError.BadName
        if (!SpotLimits.validCoords(lat, lng)) throw HeadstartError.BadCoords
        val payload = mutableMapOf<String, Any?>(
            "pairId" to pairId,
            "name" to cleanName,
            "lat" to lat,
            "lng" to lng,
            "leadTimeMin" to SpotLimits.clampLeadTimeMin(leadTimeMin),
            "radiusM" to SpotLimits.clampRadiusM(radiusM),
        )
        if (spotId != null) payload["spotId"] = spotId
        val res = callables.call("upsertSpot", payload)
        return res.str("spotId") ?: spotId ?: throw HeadstartError.Unknown("upsertSpot-no-id")
    }

    suspend fun deleteSpot(spotId: String) {
        callables.call("deleteSpot", mapOf("spotId" to spotId))
    }
}
