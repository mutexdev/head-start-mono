package app.headstart.tracking

import android.Manifest
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.BatteryManager
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import app.headstart.ServiceLocator
import app.headstart.core.minutesAway
import app.headstart.data.PositionUpload
import app.headstart.data.PositionUploader
import app.headstart.push.Notifications
import app.headstart.push.ONGOING_TRIP_ID
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch

/**
 * The only place in the app that talks to the OS location APIs.
 *
 * It owns nothing clever: [TrackingPhaseController] decides the phase, the request
 * parameters and which fixes are worth uploading; [PositionUploader] owns the offline
 * buffer. This class wires them to FusedLocationProviderClient and to the trip document,
 * and stops the moment the trip leaves `driving`.
 *
 * Runs as a `location` foreground service with a while-in-use grant. We never ask for
 * ACCESS_BACKGROUND_LOCATION — see the plan header for why.
 *
 * It NEVER sends an `arrived` push. Arrival is the server's decision; all this service
 * does is keep `trips/{id}/positions` fed so `onPositionWrite` can make it.
 */
class LocationForegroundService : Service() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private lateinit var client: FusedLocationProviderClient
    private var controller: TrackingPhaseController? = null
    private var uploader: PositionUploader? = null
    private var tripId: String? = null
    private var currentParams: LocationParams? = null
    private var tripJob: Job? = null
    private var guardJob: Job? = null
    private var lastEtaSeconds: Int? = null
    private var lastProgressPct: Int? = null
    private var partnerName: String = "your ride"

    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            val c = controller ?: return
            val u = uploader ?: return
            for (location in result.locations) {
                val fix = LocationFix(
                    lat = location.latitude,
                    lng = location.longitude,
                    accuracyM = location.accuracy.toDouble(),
                    speedMps = location.speed.toDouble(),
                    tsMs = location.time,
                )
                when (val decision = c.onFix(fix)) {
                    is FixDecision.Upload -> scope.launch {
                        runCatching {
                            u.submit(
                                PositionUpload(
                                    lat = decision.fix.lat,
                                    lng = decision.fix.lng,
                                    accuracyM = decision.fix.accuracyM,
                                    speedMps = decision.fix.speedMps,
                                    ts = decision.fix.tsMs,
                                    // Android leaves etaSec null: the server routes (addendum F).
                                    etaSec = null,
                                ),
                            )
                        }.onFailure { Log.w(TAG, "upload failed", it) }
                    }
                    is FixDecision.Skip -> Log.d(TAG, "skipped fix: ${decision.reason}")
                }
            }
            applyBatteryLevel()
            reapplyParamsIfPhaseChanged()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        client = LocationServices.getFusedLocationProviderClient(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopTracking()
                return START_NOT_STICKY
            }
            ACTION_START -> start(intent)
            else -> {
                // Restarted by the system with a null intent and nothing to track.
                if (tripId == null) stopTracking()
            }
        }
        return START_STICKY
    }

    private fun start(intent: Intent) {
        val id = intent.getStringExtra(EXTRA_TRIP_ID) ?: return stopTracking()
        val spotLat = intent.getDoubleExtra(EXTRA_SPOT_LAT, Double.NaN)
        val spotLng = intent.getDoubleExtra(EXTRA_SPOT_LNG, Double.NaN)
        val nearBand = intent.getDoubleExtra(EXTRA_NEAR_BAND, 3_500.0)
        val radiusM = intent.getFloatExtra(EXTRA_SPOT_RADIUS, 100f)
        val startedAt = intent.getLongExtra(EXTRA_STARTED_AT, System.currentTimeMillis())
        partnerName = intent.getStringExtra(EXTRA_PARTNER_NAME) ?: "your ride"
        if (spotLat.isNaN() || spotLng.isNaN()) return stopTracking()
        if (tripId == id) return // already tracking this trip

        tripId = id
        ServiceLocator.prefs.activeTripId = id
        controller = TrackingPhaseController(spotLat, spotLng, nearBand, startedAt)
        uploader = PositionUploader(id, ServiceLocator.positionSink)
        currentParams = null

        // targetSdk 36 gives us five seconds from startForegroundService to here.
        ServiceCompat.startForeground(
            this,
            ONGOING_TRIP_ID,
            Notifications.ongoingTrip(this, "Sharing with $partnerName", "Working out your ETA…"),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            } else {
                0
            },
        )

        requestUpdates()
        registerArrivalGeofence(this, id, spotLat, spotLng, radiusM)
        observeTrip(id)
        startGuard()
    }

    /** Applies the controller's parameters, re-requesting only when they actually change. */
    private fun requestUpdates() {
        val c = controller ?: return
        val params = c.params()
        if (params == currentParams) return
        currentParams = params

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "no location permission; stopping")
            stopTracking()
            return
        }

        val priority = when (params.priority) {
            LocationPriority.HIGH -> Priority.PRIORITY_HIGH_ACCURACY
            LocationPriority.BALANCED -> Priority.PRIORITY_BALANCED_POWER_ACCURACY
        }
        val request = LocationRequest.Builder(priority, params.minIntervalMs)
            .setMinUpdateIntervalMillis(params.minIntervalMs / 2)
            .setMinUpdateDistanceMeters(params.minDisplacementM)
            .setWaitForAccurateLocation(params.priority == LocationPriority.HIGH)
            .build()

        client.removeLocationUpdates(callback)
        @Suppress("MissingPermission")
        client.requestLocationUpdates(request, callback, Looper.getMainLooper())
        Log.i(TAG, "location updates: $params")
    }

    private fun reapplyParamsIfPhaseChanged() {
        val c = controller ?: return
        if (c.params() != currentParams) requestUpdates()
    }

    private fun applyBatteryLevel() {
        val c = controller ?: return
        val id = tripId ?: return
        val manager = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager ?: return
        val percent = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        // Latches: true exactly once per trip, on the first report under 15 % (addendum L).
        if (c.onBatteryPercent(percent)) {
            scope.launch {
                runCatching { ServiceLocator.tripRepository.setLowBattery(id) }
                    .onFailure { Log.w(TAG, "setLowBattery failed", it) }
            }
        }
    }

    /**
     * The trip document is the authority: it carries `phaseHint`, the live ETA for the
     * notification, and the state that ends tracking. 'I'm here' / 'Cancel' both land as
     * an `endTrip` that moves `state` out of `driving`, so this listener is also how the
     * two buttons stop the service.
     */
    private fun observeTrip(id: String) {
        tripJob?.cancel()
        tripJob = scope.launch {
            ServiceLocator.tripRepository.trip(id)
                .catch { Log.w(TAG, "trip listener failed", it) }
                .collect { trip ->
                    if (trip == null || !trip.isDriving) {
                        Log.i(TAG, "trip left driving (${trip?.state}); stopping")
                        stopTracking()
                        return@collect
                    }
                    controller?.onServerPhaseHint(trip.phaseHint)
                    reapplyParamsIfPhaseChanged()

                    lastEtaSeconds = trip.eta?.seconds
                    lastProgressPct = trip.receiverView?.progressPct
                    updateOngoingNotification()
                }
        }
    }

    private fun updateOngoingNotification() {
        val eta = lastEtaSeconds
        val body = if (eta == null) {
            "Working out your ETA…"
        } else {
            "${minutesAway(eta)} min away — ends on arrival"
        }
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.notify(
            ONGOING_TRIP_ID,
            Notifications.ongoingTrip(this, "Sharing with $partnerName", body, lastProgressPct),
        )
    }

    /** The three-hour local guard, plus a periodic retry of anything still buffered. */
    private fun startGuard() {
        guardJob?.cancel()
        guardJob = scope.launch {
            while (true) {
                delay(60_000)
                uploader?.let { runCatching { it.flush() } }
                val c = controller ?: continue
                if (c.shouldStop(System.currentTimeMillis())) {
                    Log.i(TAG, "3 hour guard reached; stopping")
                    stopTracking()
                    return@launch
                }
            }
        }
    }

    private fun stopTracking() {
        client.removeLocationUpdates(callback)
        tripId?.let { removeArrivalGeofence(this) }
        tripJob?.cancel()
        guardJob?.cancel()
        tripId = null
        controller = null
        uploader = null
        currentParams = null
        ServiceLocator.prefs.activeTripId = null
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        client.removeLocationUpdates(callback)
        scope.cancel()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "HsTracking"

        const val ACTION_START = "app.headstart.action.START_TRACKING"
        const val ACTION_STOP = "app.headstart.action.STOP_TRACKING"

        private const val EXTRA_TRIP_ID = "tripId"
        private const val EXTRA_SPOT_LAT = "spotLat"
        private const val EXTRA_SPOT_LNG = "spotLng"
        private const val EXTRA_NEAR_BAND = "nearBand"
        private const val EXTRA_SPOT_RADIUS = "spotRadius"
        private const val EXTRA_STARTED_AT = "startedAt"
        private const val EXTRA_PARTNER_NAME = "partnerName"

        /**
         * Call from the UI thread, from the driver's explicit "I'm coming" tap, right
         * after `startTrip` returns — and from nowhere else.
         *
         * targetSdk 36 only permits a `location` foreground service to start while the app
         * is visible. Returns null on success, or a sentence fit to show the driver when
         * the OS refused, rather than letting ForegroundServiceStartNotAllowedException
         * take the process down.
         */
        fun start(
            context: Context,
            tripId: String,
            spotLat: Double,
            spotLng: Double,
            nearBandM: Double,
            spotRadiusM: Float,
            partnerName: String,
            startedAtMs: Long = System.currentTimeMillis(),
        ): String? {
            val intent = Intent(context, LocationForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TRIP_ID, tripId)
                putExtra(EXTRA_SPOT_LAT, spotLat)
                putExtra(EXTRA_SPOT_LNG, spotLng)
                putExtra(EXTRA_NEAR_BAND, nearBandM)
                putExtra(EXTRA_SPOT_RADIUS, spotRadiusM)
                putExtra(EXTRA_STARTED_AT, startedAtMs)
                putExtra(EXTRA_PARTNER_NAME, partnerName)
            }
            return try {
                ContextCompat.startForegroundService(context, intent)
                null
            } catch (t: Throwable) {
                Log.w(TAG, "startForegroundService refused", t)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    t is android.app.ForegroundServiceStartNotAllowedException
                ) {
                    "Keep Headstart open to start sharing your location."
                } else {
                    "Couldn't start location sharing. ${t.message.orEmpty()}".trim()
                }
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, LocationForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            runCatching { context.startService(intent) }
                .onFailure { Log.w(TAG, "stop() ignored: service not running", it) }
        }
    }
}
