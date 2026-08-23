package app.headstart.tracking

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import kotlinx.coroutines.tasks.await

/**
 * Plan Task 13 Step 1. Created here in batch and5 rather than and4: `GeofenceReceiver`
 * cannot compile without it, and SpotEditScreen's "Use my current location" button (and4)
 * is wired to a host callback that has nothing to call until this exists. The screen's own
 * `DeviceLocation(lat, lng)` type stays where it is — the host adapts between the two.
 */
data class SimpleLocation(val lat: Double, val lng: Double, val accuracyM: Double)

fun hasLocationPermission(context: Context): Boolean =
    ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED

/**
 * One fresh fix. Used to place a new spot, to seed `startTrip`, and by the geofence backup
 * wake-up. Returns null when the permission is missing or the device could not produce a
 * fix in time.
 */
suspend fun currentLocation(context: Context): SimpleLocation? {
    if (!hasLocationPermission(context)) return null
    val client = LocationServices.getFusedLocationProviderClient(context)
    val cts = CancellationTokenSource()
    return try {
        @Suppress("MissingPermission")
        val location = client.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, cts.token).await()
        location?.let { SimpleLocation(it.latitude, it.longitude, it.accuracy.toDouble()) }
    } catch (t: Throwable) {
        null
    }
}
