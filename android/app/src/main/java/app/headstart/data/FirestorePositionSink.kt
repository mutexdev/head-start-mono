package app.headstart.data

import com.google.firebase.Timestamp
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.tasks.await
import java.util.Date

private const val THIRTY_DAYS_MS = 30L * 24L * 60L * 60L * 1000L

/**
 * `trips/{tripId}/positions/{autoId}` — the only path clients are allowed to write.
 * Addendum §J: exactly seven keys, lat/lng/accuracyM/speedMps/ts/expireAt plus optional
 * etaSec. The security rules reject any extra field, so do not add one here without
 * changing firestore.rules in the backend plan first.
 *
 * On Android `etaSec` is always null (addendum §F — the server does the routing), so that
 * branch never fires; it exists only so this sink stays symmetric with the iOS twin.
 */
class FirestorePositionSink(private val db: FirebaseFirestore) : PositionSink {
    override suspend fun write(tripId: String, position: PositionUpload) {
        val data = hashMapOf<String, Any>(
            "lat" to position.lat,
            "lng" to position.lng,
            "accuracyM" to position.accuracyM,
            "speedMps" to position.speedMps,
            "ts" to position.ts,
            "expireAt" to Timestamp(Date(position.ts + THIRTY_DAYS_MS)),
        )
        position.etaSec?.let { data["etaSec"] = it }
        db.collection("trips").document(tripId).collection("positions").add(data).await()
    }
}
