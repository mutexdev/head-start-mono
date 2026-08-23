package app.headstart.ui

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import app.headstart.Role
import app.headstart.ServiceLocator
import app.headstart.core.HeadstartConfig
import app.headstart.core.greetingFor
import app.headstart.data.InviteCode
import app.headstart.push.NudgeBus
import app.headstart.ui.driver.DriverHomeScreen
import app.headstart.ui.driver.DriverNudgeSheet
import app.headstart.ui.driver.DriverTripScreen
import app.headstart.ui.onboarding.PhoneScreen
import app.headstart.ui.onboarding.ProfileScreen
import app.headstart.ui.onboarding.VerifyScreen
import app.headstart.ui.onboarding.WelcomeScreen
import app.headstart.ui.pair.PairEmptyScreen
import app.headstart.ui.pair.PairEnterScreen
import app.headstart.ui.pair.PairInviteScreen
import app.headstart.ui.receiver.ReceiverHomeScreen
import app.headstart.ui.receiver.ReceiverTripScreen
import app.headstart.ui.settings.SettingsScreen
import app.headstart.ui.spots.DeviceLocation
import app.headstart.ui.spots.SpotEditScreen
import app.headstart.ui.spots.SpotsScreen
import kotlinx.coroutines.delay
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

object Routes {
    const val WELCOME = "welcome"
    const val PHONE = "phone"
    const val VERIFY = "verify"
    const val PROFILE = "profile"
    const val PAIR_EMPTY = "pairEmpty"
    const val PAIR_INVITE = "pairInvite"
    const val PAIR_ENTER = "pairEnter"
    const val HOME = "home"
    const val SPOTS = "spots"
    const val SPOT_EDIT = "spotEdit"
    const val SETTINGS = "settings"
}

/** Routes that only make sense once a pair exists. */
private val PAIRED_ONLY = setOf(Routes.HOME, Routes.SPOTS, Routes.SPOT_EDIT, Routes.SETTINGS)

/** Routes we leave the moment a pair appears. */
private val PAIRING_ROUTES = setOf(Routes.PAIR_EMPTY, Routes.PAIR_INVITE, Routes.PAIR_ENTER)

/**
 * One graph, driven by three facts: signed in?, paired?, is there a live trip? Everything
 * else is a push from the user.
 *
 * Every screen in the app is stateless, so this function is where each one is joined to
 * [AppViewModel]. It holds only ephemeral navigation scratch — which spot is being edited,
 * whether the invite code was just copied, and the one-second tick the trip screens need.
 */
@Composable
fun HeadstartNavGraph(
    /** From a `headstart://pair/{code}` intent, if the app was opened by one. */
    deepLinkCode: String? = null,
    navController: NavHostController = rememberNavController(),
) {
    val context = LocalContext.current
    val vm: AppViewModel = viewModel()

    val uid by vm.uid.collectAsStateWithLifecycle()
    val pair by vm.pair.collectAsStateWithLifecycle()
    val pendingInvite by vm.pendingInvite.collectAsStateWithLifecycle()
    val inviteCode by vm.inviteCode.collectAsStateWithLifecycle()
    val spots by vm.spots.collectAsStateWithLifecycle()
    val trip by vm.activeTrip.collectAsStateWithLifecycle()
    val replies by vm.replies.collectAsStateWithLifecycle()
    val role by vm.role.collectAsStateWithLifecycle()
    val busy by vm.busy.collectAsStateWithLifecycle()
    val error by vm.error.collectAsStateWithLifecycle()
    val showGuidance by vm.showBatteryGuidance.collectAsStateWithLifecycle()
    val partnerName by vm.partnerName.collectAsStateWithLifecycle()
    val showNudge by NudgeBus.showDidYouLeave.collectAsStateWithLifecycle()
    val dialCode by vm.dialCode.collectAsStateWithLifecycle()
    val national by vm.national.collectAsStateWithLifecycle()
    val resendIn by vm.resendInSeconds.collectAsStateWithLifecycle()
    val deviceLocation by vm.deviceLocation.collectAsStateWithLifecycle()
    val locating by vm.locating.collectAsStateWithLifecycle()
    val hideExactPosition by vm.hideExactPosition.collectAsStateWithLifecycle()
    val useCloud by vm.useCloud.collectAsStateWithLifecycle()

    var editingSpotId by remember { mutableStateOf<String?>(null) }
    var copied by remember { mutableStateOf(false) }
    var pendingCode by remember(deepLinkCode) { mutableStateOf(deepLinkCode) }

    val currentRoute = navController.currentBackStackEntryAsState().value?.destination?.route
    val nowMs = rememberNowMs()

    fun goHomeOrPairing() {
        val target = if (pair == null) Routes.PAIR_EMPTY else Routes.HOME
        navController.navigate(target) { popUpTo(0) }
    }

    val permissions = rememberPermissionFlow(onFinished = { goHomeOrPairing() })

    // Signing out from anywhere drops back to Welcome; signing in or pairing moves forward.
    // The start destination is only evaluated once, so these corrections are what handle a
    // cold start where `pair` has not arrived from Firestore yet.
    LaunchedEffect(uid, pair?.id, currentRoute, pendingCode) {
        when {
            uid == null ->
                if (currentRoute != null && currentRoute != Routes.WELCOME &&
                    currentRoute != Routes.PHONE && currentRoute != Routes.VERIFY
                ) {
                    navController.navigate(Routes.WELCOME) { popUpTo(0) }
                }

            pair == null ->
                if (currentRoute in PAIRED_ONLY) {
                    navController.navigate(Routes.PAIR_EMPTY) { popUpTo(0) }
                }

            // Paired. Leave the pairing screens — unless a deep link deliberately put us on
            // one, in which case the user asked to be there.
            pendingCode == null && currentRoute in PAIRING_ROUTES ->
                navController.navigate(Routes.HOME) { popUpTo(0) }
        }
    }

    // A deep-linked invite jumps straight to the code screen once signed in.
    LaunchedEffect(uid, pendingCode) {
        val code = pendingCode
        if (uid != null && code != null && currentRoute != Routes.PAIR_ENTER) {
            Log.i(HeadstartConfig.LOG_TAG, "deep link -> pair entry, code=$code")
            navController.navigate(Routes.PAIR_ENTER)
        }
    }

    LaunchedEffect(copied) {
        if (copied) {
            delay(1_600)
            copied = false
        }
    }

    // Computed ONCE. navigation-compose rebuilds the graph and resets the back stack
    // whenever `startDestination` changes, so a live `when` here would throw away the
    // Profile screen the instant sign-in lands. Later changes are handled by the
    // correction effect above, which navigates instead of rebuilding.
    val startDestination = remember {
        when {
            vm.uid.value == null -> Routes.WELCOME
            vm.pair.value == null -> Routes.PAIR_EMPTY
            else -> Routes.HOME
        }
    }

    NavHost(
        navController = navController,
        startDestination = startDestination,
    ) {
        composable(Routes.WELCOME) {
            WelcomeScreen(
                onGetStarted = {
                    vm.clearError()
                    navController.navigate(Routes.PHONE)
                },
                onHaveInviteCode = {
                    vm.clearError()
                    navController.navigate(Routes.PHONE)
                },
            )
        }

        composable(Routes.PHONE) {
            PhoneScreen(
                onBack = { navController.popBackStack() },
                onSendCode = { _, dial, number ->
                    val activity = context.findActivity() ?: return@PhoneScreen
                    vm.sendCode(
                        activity = activity,
                        dialCode = dial,
                        national = number,
                        onCodeSent = { navController.navigate(Routes.VERIFY) },
                        onSignedIn = { navController.navigate(Routes.PROFILE) },
                    )
                },
                initialDialCode = dialCode,
                initialNational = national,
                sending = busy,
                errorMessage = error,
            )
        }

        composable(Routes.VERIFY) {
            VerifyScreen(
                dialCode = dialCode,
                national = national,
                onBack = { navController.popBackStack() },
                onChangeNumber = { navController.popBackStack() },
                onResend = {
                    val activity = context.findActivity() ?: return@VerifyScreen
                    vm.sendCode(activity, dialCode, national, resend = true)
                },
                onVerify = { code ->
                    vm.verify(code) { navController.navigate(Routes.PROFILE) }
                },
                resendInSeconds = resendIn,
                verifying = busy,
                errorMessage = error,
            )
        }

        composable(Routes.PROFILE) {
            ProfileScreen(
                onBack = { navController.popBackStack() },
                onAllowAndContinue = { name ->
                    vm.onSignedIn(name)
                    permissions.start(context)
                },
                initialName = ServiceLocator.prefs.displayName.orEmpty(),
                saving = busy,
                errorMessage = error,
            )
        }

        composable(Routes.PAIR_EMPTY) {
            PairEmptyScreen(
                onInvite = {
                    vm.clearError()
                    navController.navigate(Routes.PAIR_INVITE)
                },
                onEnterCode = {
                    vm.clearError()
                    navController.navigate(Routes.PAIR_ENTER)
                },
            )
        }

        composable(Routes.PAIR_INVITE) {
            LaunchedEffect(Unit) { vm.ensureInvite() }
            val code = inviteCode ?: pendingInvite?.inviteCode?.takeIf { it.isNotBlank() }
            PairInviteScreen(
                code = code,
                onBack = { navController.popBackStack() },
                onShare = { text -> context.shareText(text) },
                onCopy = {
                    context.copyToClipboard(it)
                    copied = true
                },
                copied = copied,
                errorMessage = error,
            )
        }

        composable(Routes.PAIR_ENTER) {
            PairEnterScreen(
                onBack = {
                    pendingCode = null
                    navController.popBackStack()
                },
                onPair = { code ->
                    vm.acceptPair(code) {
                        pendingCode = null
                        navController.navigate(Routes.HOME) { popUpTo(0) }
                    }
                },
                prefilledCode = pendingCode,
                pairing = busy,
                errorMessage = error,
            )
        }

        composable(Routes.HOME) {
            val liveTrip = trip
            val me = uid
            when {
                liveTrip != null && liveTrip.isDriving && liveTrip.isDriver(me) ->
                    DriverTripScreen(
                        trip = liveTrip,
                        partnerName = partnerName,
                        latestReply = replies.lastOrNull { it.fromUid != me },
                        nowMs = nowMs.value,
                        busy = busy,
                        error = error,
                        onRunningLate = { vm.runningLate(liveTrip.id, it) },
                        onCancel = { vm.endTrip(liveTrip.id, "cancelled") },
                        onArrived = { vm.endTrip(liveTrip.id, "arrived") },
                    )

                liveTrip != null && liveTrip.isDriving && liveTrip.isReceiver(me) ->
                    ReceiverTripScreen(
                        trip = liveTrip,
                        partnerName = partnerName,
                        sending = busy,
                        error = error,
                        onReply = { kind, text -> vm.sendReply(liveTrip.id, kind, text) },
                        nowMs = nowMs.value,
                    )

                role == Role.WAITING -> {
                    val armedSpot = spots.firstOrNull { it.id == liveTrip?.spotId }
                        ?: spots.firstOrNull()
                    ReceiverHomeScreen(
                        partnerName = partnerName,
                        spot = armedSpot,
                        role = role,
                        nextSchedule = null, // schedules are M3
                        arming = busy,
                        armed = liveTrip?.isArmed == true,
                        error = error,
                        onRoleChange = vm::setRole,
                        onLeadTimeChange = { minutes ->
                            armedSpot?.let { vm.setLeadTime(it, minutes) }
                        },
                        onPingMe = { armedSpot?.let { vm.armTrip(it) } },
                        onSettings = { navController.navigate(Routes.SETTINGS) },
                        onManageSpots = { navController.navigate(Routes.SPOTS) },
                    )
                }

                else ->
                    DriverHomeScreen(
                        greeting = greetingFor(LocalDateTime.now()),
                        driverName = ServiceLocator.prefs.displayName ?: "there",
                        partnerName = partnerName,
                        spots = spots,
                        // Matched by NAME inside the screen, so resolve the armed trip's
                        // spotId to the live spot rather than trusting the trip's snapshot.
                        armedSpotName = liveTrip?.takeIf { it.isArmed }?.let { armed ->
                            spots.firstOrNull { it.id == armed.spotId }?.name ?: armed.spotName
                        },
                        role = role,
                        starting = busy,
                        error = error,
                        onRoleChange = vm::setRole,
                        onStart = { vm.startTrip(context, it) },
                        onOpenSpot = {
                            editingSpotId = it.id
                            vm.clearDeviceLocation()
                            navController.navigate(Routes.SPOT_EDIT)
                        },
                        onManageSpots = { navController.navigate(Routes.SPOTS) },
                        onSettings = { navController.navigate(Routes.SETTINGS) },
                    )
            }
        }

        composable(Routes.SPOTS) {
            SpotsScreen(
                spots = spots,
                partnerName = partnerName,
                onAdd = {
                    editingSpotId = null
                    vm.clearDeviceLocation()
                    vm.clearError()
                    navController.navigate(Routes.SPOT_EDIT)
                },
                onOpen = {
                    editingSpotId = it.id
                    vm.clearDeviceLocation()
                    vm.clearError()
                    navController.navigate(Routes.SPOT_EDIT)
                },
                onBack = { navController.popBackStack() },
            )
        }

        composable(Routes.SPOT_EDIT) {
            val existing = spots.firstOrNull { it.id == editingSpotId }
            SpotEditScreen(
                existing = existing,
                partnerName = partnerName,
                onBack = { navController.popBackStack() },
                onUseCurrentLocation = { vm.locate(context) },
                onSave = { name, lat, lng, leadTimeMin, radiusM ->
                    vm.saveSpot(existing?.id, name, lat, lng, leadTimeMin, radiusM) {
                        navController.popBackStack()
                    }
                },
                onDelete = {
                    existing?.let { spot ->
                        vm.deleteSpot(spot.id) { navController.popBackStack() }
                    }
                },
                deviceLocation = deviceLocation?.let { DeviceLocation(it.first, it.second) },
                locating = locating,
                saving = busy,
                errorMessage = error,
            )
        }

        composable(Routes.SETTINGS) {
            SettingsScreen(
                partnerName = partnerName,
                pairId = pair?.id,
                pairedSince = pair?.createdAtMs?.let { pairedSince(it) },
                hideExactPosition = hideExactPosition,
                useCloud = useCloud,
                error = error,
                onBack = { navController.popBackStack() },
                onHideExactPositionChange = vm::setHideExactPosition,
                onUseCloudChange = vm::setUseCloud,
                onUnpair = { vm.unpair { navController.navigate(Routes.PAIR_EMPTY) { popUpTo(0) } } },
                onSignOut = { vm.signOut { navController.navigate(Routes.WELCOME) { popUpTo(0) } } },
            )
        }
    }

    if (showNudge) {
        val liveTrip = trip
        DriverNudgeSheet(
            partnerName = partnerName,
            onDismiss = { NudgeBus.clear() },
            onOnMyWay = { NudgeBus.clear() },
            onCancelTrip = {
                NudgeBus.clear()
                liveTrip?.let { vm.endTrip(it.id, "cancelled") }
            },
        )
    }

    if (showGuidance) {
        BatteryGuidanceDialog(onDismiss = vm::dismissBatteryGuidance)
    }
}

/**
 * One tick a second, read only inside the trip branches so the rest of the graph does not
 * recompose with it. The trip screens take `nowMs` as a parameter rather than reading the
 * clock themselves — that is what keeps the alert ladder's timings testable.
 */
@Composable
private fun rememberNowMs(): State<Long> {
    val state = remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1_000)
            state.longValue = System.currentTimeMillis()
        }
    }
    return state
}

private val PAIRED_SINCE: DateTimeFormatter = DateTimeFormatter.ofPattern("d MMMM", Locale.US)

private fun pairedSince(epochMs: Long): String =
    "since " + Instant.ofEpochMilli(epochMs).atZone(ZoneId.systemDefault()).format(PAIRED_SINCE)

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is android.content.ContextWrapper -> baseContext.findActivity()
    else -> null
}

private fun Context.copyToClipboard(code: String) {
    val manager = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
    manager.setPrimaryClip(ClipData.newPlainText("Headstart invite", code))
}

private fun Context.shareText(text: String) {
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, text)
    }
    runCatching { startActivity(Intent.createChooser(intent, "Share your invite")) }
        .onFailure { Log.w(HeadstartConfig.LOG_TAG, "no share target", it) }
}

/** Kept next to the graph so the scheme in the manifest and the parser can never drift. */
internal fun inviteCodeFromIntentData(data: String?): String? = InviteCode.fromDeepLink(data)
