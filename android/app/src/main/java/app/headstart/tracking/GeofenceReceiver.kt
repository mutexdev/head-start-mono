package app.headstart.tracking

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.content.ContextCompat
import app.headstart.ServiceLocator
import app.headstart.data.PositionUpload
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

private const val TAG = "HsGeofence"
private const val GEOFENCE_ID = "headstart-arrival"

@SuppressLint("MissingPermission")
fun registerArrivalGeofence(
    context: Context,
    tripId: String,
    lat: Double,
    lng: Double,
    radiusM: Float,
) {
    if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
        != PackageManager.PERMISSION_GRANTED
    ) return

    val geofence = Geofence.Builder()
        .setRequestId(GEOFENCE_ID)
        .setCircularRegion(lat, lng, radiusM)
        .setExpirationDuration(3 * 60 * 60 * 1000L)
        .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER)
        .build()

    val request = GeofencingRequest.Builder()
        .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
        .addGeofence(geofence)
        .build()

    LocationServices.getGeofencingClient(context)
        .addGeofences(request, geofencePendingIntent(context))
        .addOnSuccessListener { Log.i(TAG, "arrival geofence registered for $tripId") }
        .addOnFailureListener { Log.w(TAG, "geofence not registered", it) }
}

fun removeArrivalGeofence(context: Context) {
    LocationServices.getGeofencingClient(context).removeGeofences(geofencePendingIntent(context))
}

private fun geofencePendingIntent(context: Context): PendingIntent =
    PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, GeofenceReceiver::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

/**
 * Backup arrival wake-up. **It does not decide that the driver arrived** — the contract is
 * explicit that arrival is the server's call, and this receiver sends no push and starts no
 * service. All it does is force one accurate fix into `positions` so `onPositionWrite` sees
 * the driver inside `spot.radiusM` even if the app was starved of location updates on the
 * last leg.
 */
class GeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) {
            Log.w(TAG, "geofence error ${event.errorCode}")
            return
        }
        if (event.geofenceTransition != Geofence.GEOFENCE_TRANSITION_ENTER) return

        val tripId = ServiceLocator.prefs.activeTripId ?: return
        val pending = goAsync()
        val appContext = context.applicationContext
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val here = currentLocation(appContext)
                if (here != null) {
                    ServiceLocator.positionSink.write(
                        tripId,
                        PositionUpload(
                            lat = here.lat,
                            lng = here.lng,
                            accuracyM = here.accuracyM,
                            speedMps = 0.0,
                            ts = System.currentTimeMillis(),
                        ),
                    )
                    Log.i(TAG, "arrival geofence pushed one fix for $tripId")
                }
            } catch (t: Throwable) {
                Log.w(TAG, "geofence upload failed", t)
            } finally {
                pending.finish()
            }
        }
    }
}
