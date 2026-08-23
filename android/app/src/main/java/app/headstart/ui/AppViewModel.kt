package app.headstart.ui

import android.app.Activity
import android.content.Context
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.headstart.Role
import app.headstart.ServiceLocator
import app.headstart.core.HeadstartError
import app.headstart.core.toHeadstartError
import app.headstart.data.PARTNER_NAME_FALLBACK
import app.headstart.data.PairInfo
import app.headstart.data.PhoneNumber
import app.headstart.data.Reply
import app.headstart.data.SendCodeResult
import app.headstart.data.Spot
import app.headstart.data.Trip
import app.headstart.push.PushTokens
import app.headstart.tracking.LocationForegroundService
import app.headstart.tracking.currentLocation
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.retryWhen
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * Owns every Flow and every mutation in the app so the screens can stay stateless. One
 * instance, scoped to MainActivity: the listeners it registers are exactly the ones the
 * contract allows — the pair (`members array-contains uid`), that pair's spots, the active
 * trip, and that trip's replies. No screen touches a repository directly.
 *
 * Deviations from the plan doc's Task 20, all forced by the shipped screen signatures:
 *  - the onboarding screens (Phone/Verify/Profile) are stateless, so the OTP flow lives
 *    here too rather than inside them;
 *  - `endTrip` does NOT call `LocationForegroundService.stop`. The service's own trip
 *    listener stops it the moment `state` leaves `driving`, and calling both races the
 *    ongoing notification's removal;
 *  - the partner's name comes from `PairInfo.partnerName(uid)` (addendum §M) and from
 *    nowhere else. `Prefs.displayName` is MY name, not theirs.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class AppViewModel : ViewModel() {

    private val auth = ServiceLocator.authRepository
    private val pairs = ServiceLocator.pairRepository
    private val spotsRepo = ServiceLocator.spotRepository
    private val trips = ServiceLocator.tripRepository
    private val prefs = ServiceLocator.prefs

    // ---------- the three facts the nav graph is built on ----------

    val uid: StateFlow<String?> =
        auth.uidFlow()
            .resilient("auth")
            .stateIn(viewModelScope, SharingStarted.Eagerly, auth.uid)

    val pair: StateFlow<PairInfo?> = uid
        .flatMapLatest { id -> if (id == null) flowOf(null) else pairs.activePair(id) }
        .resilient("pair")
        .stateIn(viewModelScope, SharingStarted.Eagerly, null)

    /** The invite this user created that nobody has accepted yet — drives PairInvite. */
    val pendingInvite: StateFlow<PairInfo?> = uid
        .flatMapLatest { id -> if (id == null) flowOf(null) else pairs.pendingInvite(id) }
        .resilient("pendingInvite")
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    val spots: StateFlow<List<Spot>> = pair
        .flatMapLatest { p -> if (p == null) flowOf(emptyList()) else spotsRepo.spots(p.id) }
        .resilient("spots")
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val activeTrip: StateFlow<Trip?> = combine(pair, uid) { p, id -> p to id }
        .flatMapLatest { (p, id) -> if (p == null) flowOf(null) else trips.activeTrip(p.id, id) }
        .resilient("activeTrip")
        .stateIn(viewModelScope, SharingStarted.Eagerly, null)

    val replies: StateFlow<List<Reply>> = activeTrip
        .map { it?.id }
        .flatMapLatest { id -> if (id == null) flowOf(emptyList()) else trips.replies(id) }
        .resilient("replies")
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    /**
     * Addendum §M: `pairs/{pairId}.memberNames` is the single source. Falls back to
     * "Your partner" until the other side has registered a display name.
     */
    val partnerName: StateFlow<String> = combine(pair, uid) { p, id ->
        if (p != null && id != null) p.partnerName(id) else PARTNER_NAME_FALLBACK
    }.stateIn(viewModelScope, SharingStarted.Eagerly, PARTNER_NAME_FALLBACK)

    /**
     * A Firestore snapshot listener that reports an error CLOSES its callbackFlow
     * (`core/FirestoreFlows.kt`), and a plain `catch { emit(fallback) }` would then end the
     * chain for good — one transient `RESOURCE_EXHAUSTED`/`Received Goaway` from the watch
     * stream and the app goes permanently blind to the trip, which is exactly what happened
     * on the AVD dry-run before this existed.
     *
     * `retryWhen` re-subscribes upstream, which re-registers the listener. Backoff is capped
     * so a genuinely denied read retries slowly rather than spinning. Nothing is swallowed
     * silently: every failure is logged under the app's own tag.
     */
    private fun <T> Flow<T>.resilient(what: String): Flow<T> = retryWhen { cause, attempt ->
        Log.w(TAG, "$what listener failed (attempt $attempt); re-registering", cause)
        delay(minOf(1_000L * (attempt + 1), 15_000L))
        true
    }

    // ---------- role ----------

    private val _roleChoice = MutableStateFlow(prefs.role)

    /**
     * A live trip forces the role that matches which side of it you are on — you cannot be
     * "waiting" while your own phone is uploading positions. With no trip running, the last
     * choice is remembered in Prefs.
     */
    val role: StateFlow<Role> = combine(_roleChoice, activeTrip, uid) { choice, trip, id ->
        when {
            trip == null || id == null -> choice
            trip.isDriver(id) -> Role.DRIVING
            trip.isReceiver(id) -> Role.WAITING
            else -> choice
        }
    }.stateIn(viewModelScope, SharingStarted.Eagerly, prefs.role)

    fun setRole(role: Role) {
        prefs.role = role
        _roleChoice.value = role
    }

    // ---------- transient UI state ----------

    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    private val _showBatteryGuidance = MutableStateFlow(false)
    val showBatteryGuidance: StateFlow<Boolean> = _showBatteryGuidance

    fun clearError() {
        _error.value = null
    }

    fun dismissBatteryGuidance() {
        _showBatteryGuidance.value = false
    }

    private fun fail(t: Throwable) {
        _error.value = (t as? HeadstartError ?: t.toHeadstartError()).userMessage
    }

    // ---------- sign-in ----------

    private val _verificationId = MutableStateFlow("")
    val verificationId: StateFlow<String> = _verificationId

    private val _dialCode = MutableStateFlow("+880")
    val dialCode: StateFlow<String> = _dialCode

    private val _national = MutableStateFlow("")
    val national: StateFlow<String> = _national

    private val _resendInSeconds = MutableStateFlow(0)
    val resendInSeconds: StateFlow<Int> = _resendInSeconds

    /**
     * Sends the OTP. [onCodeSent] fires only when an SMS (or, against the Auth emulator, a
     * retrievable code) is actually pending; Play auto-retrieval signs in directly instead.
     */
    fun sendCode(
        activity: Activity,
        dialCode: String,
        national: String,
        resend: Boolean = false,
        onCodeSent: () -> Unit = {},
        onSignedIn: () -> Unit = {},
    ) {
        val e164 = PhoneNumber.toE164(dialCode, national)
        if (e164 == null) {
            _error.value = HeadstartError.InvalidPhone.userMessage
            return
        }
        if (_busy.value) return
        _busy.value = true
        _error.value = null
        _dialCode.value = dialCode
        _national.value = national
        viewModelScope.launch {
            try {
                when (val result = auth.sendCode(activity, e164, resend)) {
                    is SendCodeResult.CodeSent -> {
                        _verificationId.value = result.verificationId
                        startResendCountdown()
                        onCodeSent()
                    }
                    is SendCodeResult.AutoRetrieved -> {
                        auth.signIn(result.credential)
                        onSignedIn()
                    }
                }
            } catch (t: Throwable) {
                fail(t)
            } finally {
                _busy.value = false
            }
        }
    }

    private fun startResendCountdown() {
        viewModelScope.launch {
            _resendInSeconds.value = 30
            while (_resendInSeconds.value > 0) {
                delay(1_000)
                _resendInSeconds.value -= 1
            }
        }
    }

    fun verify(code: String, onVerified: () -> Unit) {
        if (_busy.value) return
        _busy.value = true
        _error.value = null
        viewModelScope.launch {
            try {
                auth.verify(_verificationId.value, code)
                onVerified()
            } catch (t: Throwable) {
                fail(t)
            } finally {
                _busy.value = false
            }
        }
    }

    /**
     * ProfileScreen's "Allow and continue". The name rides on `registerPushToken`, which is
     * how the server fills `pairs/{pairId}.memberNames` for the other side to read.
     */
    fun onSignedIn(displayName: String?) {
        if (!displayName.isNullOrBlank()) prefs.displayName = displayName.trim()
        viewModelScope.launch {
            runCatching { PushTokens.syncIfNeeded(displayName = prefs.displayName, force = true) }
        }
    }

    fun signOut(onDone: () -> Unit) {
        auth.signOut()
        prefs.clearAccountScoped()
        _roleChoice.value = prefs.role
        _inviteCode.value = null
        inviteRequested = false
        onDone()
    }

    // ---------- pairing ----------

    private val _inviteCode = MutableStateFlow<String?>(null)
    val inviteCode: StateFlow<String?> = _inviteCode
    private var inviteRequested = false

    /** Called when PairInvite opens. Creates the pair once; the code is stable after that. */
    fun ensureInvite() {
        if (_inviteCode.value != null) return
        pendingInvite.value?.inviteCode?.takeIf { it.isNotBlank() }?.let {
            _inviteCode.value = it
            return
        }
        if (inviteRequested) return
        inviteRequested = true
        _busy.value = true
        _error.value = null
        viewModelScope.launch {
            try {
                _inviteCode.value = pairs.createPair().inviteCode
            } catch (t: Throwable) {
                inviteRequested = false
                fail(t)
            } finally {
                _busy.value = false
            }
        }
    }

    fun acceptPair(rawCode: String, onPaired: () -> Unit) {
        if (_busy.value) return
        _busy.value = true
        _error.value = null
        viewModelScope.launch {
            try {
                pairs.acceptPair(rawCode)
                onPaired()
            } catch (t: Throwable) {
                fail(t)
            } finally {
                _busy.value = false
            }
        }
    }

    fun unpair(onDone: () -> Unit) {
        val pairId = pair.value?.id ?: return onDone()
        viewModelScope.launch {
            runCatching { pairs.revokePair(pairId) }.onFailure { fail(it) }
            _inviteCode.value = null
            inviteRequested = false
            onDone()
        }
    }

    // ---------- spots ----------

    private val _deviceLocation = MutableStateFlow<Pair<Double, Double>?>(null)
    val deviceLocation: StateFlow<Pair<Double, Double>?> = _deviceLocation

    private val _locating = MutableStateFlow(false)
    val locating: StateFlow<Boolean> = _locating

    fun locate(context: Context) {
        if (_locating.value) return
        _locating.value = true
        viewModelScope.launch {
            val here = currentLocation(context)
            if (here == null) {
                _error.value = HeadstartError.BadCoords.userMessage
            } else {
                _deviceLocation.value = here.lat to here.lng
            }
            _locating.value = false
        }
    }

    fun clearDeviceLocation() {
        _deviceLocation.value = null
    }

    fun saveSpot(
        spotId: String?,
        name: String,
        lat: Double,
        lng: Double,
        leadTimeMin: Int,
        radiusM: Int,
        onSaved: () -> Unit,
    ) {
        val pairId = pair.value?.id
        if (pairId == null) {
            _error.value = HeadstartError.NotPaired.userMessage
            return
        }
        if (_busy.value) return
        _busy.value = true
        _error.value = null
        viewModelScope.launch {
            try {
                spotsRepo.upsertSpot(pairId, name, lat, lng, leadTimeMin, radiusM, spotId)
                onSaved()
            } catch (t: Throwable) {
                fail(t)
            } finally {
                _busy.value = false
            }
        }
    }

    fun deleteSpot(spotId: String, onDeleted: () -> Unit) {
        viewModelScope.launch {
            runCatching { spotsRepo.deleteSpot(spotId) }
                .onSuccess { onDeleted() }
                .onFailure { fail(it) }
        }
    }

    /** Receiver's headstart stepper on Home. Already clamped 1–30 by the screen. */
    fun setLeadTime(spot: Spot, leadTimeMin: Int) {
        viewModelScope.launch {
            runCatching {
                spotsRepo.upsertSpot(
                    pairId = spot.pairId,
                    name = spot.name,
                    lat = spot.lat,
                    lng = spot.lng,
                    leadTimeMin = leadTimeMin,
                    radiusM = spot.radiusM,
                    spotId = spot.id,
                )
            }.onFailure { fail(it) }
        }
    }

    // ---------- trips ----------

    /**
     * The driver's explicit "I'm coming" tap — the only place the foreground service is
     * ever started, because targetSdk 36 only lets a `location` FGS start while visible.
     *
     * Addendum §E: when the server says `existing`, we attach to the trip already running
     * and do NOT replay the first-start UI (the OEM dialog). We still call
     * `LocationForegroundService.start`, which is a no-op when the service is already
     * tracking that trip and a genuine re-attach when the process was killed mid-trip.
     */
    fun startTrip(context: Context, spot: Spot) {
        if (_busy.value) return
        _busy.value = true
        _error.value = null
        viewModelScope.launch {
            try {
                val here = currentLocation(context) ?: throw HeadstartError.BadCoords
                val result = trips.startTrip(
                    spotId = spot.id,
                    lat = here.lat,
                    lng = here.lng,
                    fuzzy = prefs.hideExactPosition,
                    // Android never sends etaSec — the server routes (addendum §F).
                )
                val refusal = LocationForegroundService.start(
                    context = context,
                    tripId = result.tripId,
                    spotLat = spot.lat,
                    spotLng = spot.lng,
                    nearBandM = result.bands.near,
                    spotRadiusM = spot.radiusM.toFloat(),
                    partnerName = partnerName.value,
                )
                if (refusal != null) {
                    _error.value = refusal
                } else if (!result.existing && needsBatteryGuidance() && !prefs.oemNoticeShown) {
                    _showBatteryGuidance.value = true
                }
            } catch (t: Throwable) {
                fail(t)
            } finally {
                _busy.value = false
            }
        }
    }

    /**
     * "I'm here" and "Cancel". Deliberately does not stop the service: the service's own
     * trip listener does that the instant `state` leaves `driving`.
     */
    fun endTrip(tripId: String, reason: String) {
        if (_busy.value) return
        _busy.value = true
        viewModelScope.launch {
            try {
                trips.endTrip(tripId, reason)
            } catch (t: Throwable) {
                fail(t)
            } finally {
                _busy.value = false
            }
        }
    }

    fun runningLate(tripId: String, extraMin: Int) {
        viewModelScope.launch {
            runCatching { trips.setRunningLate(tripId, extraMin) }.onFailure { fail(it) }
        }
    }

    fun sendReply(tripId: String, kind: String, text: String?) {
        if (_busy.value) return
        _busy.value = true
        viewModelScope.launch {
            try {
                trips.sendReply(tripId, kind, text)
            } catch (t: Throwable) {
                fail(t)
            } finally {
                _busy.value = false
            }
        }
    }

    /** Receiver taps "Ping me when they leave". */
    fun armTrip(spot: Spot) {
        if (_busy.value) return
        _busy.value = true
        _error.value = null
        viewModelScope.launch {
            try {
                trips.armTrip(spot.id)
            } catch (t: Throwable) {
                fail(t)
            } finally {
                _busy.value = false
            }
        }
    }

    // ---------- settings-owned preferences ----------

    private val _hideExactPosition = MutableStateFlow(prefs.hideExactPosition)
    val hideExactPosition: StateFlow<Boolean> = _hideExactPosition

    private val _useCloud = MutableStateFlow(prefs.useCloud)
    val useCloud: StateFlow<Boolean> = _useCloud

    fun setHideExactPosition(value: Boolean) {
        prefs.hideExactPosition = value
        _hideExactPosition.value = value
    }

    /** Takes effect on next launch — [HeadstartConfig.wire] runs once per process. */
    fun setUseCloud(value: Boolean) {
        prefs.useCloud = value
        _useCloud.value = value
    }

    private companion object {
        const val TAG = "HsApp"
    }
}
