// ios/Headstart/Core/ServiceLocator.swift
//
// Hand-wired singletons. No DI framework: there are under a dozen of them and none of them
// changes at runtime. Published into the view tree once, in `HeadstartApp`, as an
// `EnvironmentObject`.
//
// THIS FILE GROWS IN EVERY LATER BATCH. The `// MARK:` slots below are the append points —
// add your repository to its own slot and to `init`, and do not restructure what is already
// here. Nothing in this type is optional-by-accident: if a slot is still empty, its MARK is
// present with a one-line note saying which batch fills it.
//
// Isolation: `@MainActor`, like every repository and view model. `Callables` and
// `FirestorePositionSink` are `Sendable` value types, so they can be handed to the
// non-isolated tracking layer freely.

import Foundation
import SwiftUI
import FirebaseFirestore

@MainActor
public final class ServiceLocator: ObservableObject {

    public static let shared = ServiceLocator()

    // MARK: - Firebase handles

    /// `FirebaseApp.configure()` and the emulator wiring have already run in `AppDelegate`
    /// by the time anything touches this — `Firestore.settings` may only be assigned before
    /// the instance is first used, so nothing here may be created eagerly at launch.
    public let db: Firestore
    public let callables: Callables

    // MARK: - Auth

    /// Phone OTP, the uid, and the display name. Against the emulator this needs no APNs
    /// silent push and no reCAPTCHA — see the header of AuthRepository.swift.
    public let auth: AuthRepository

    // MARK: - Pair

    /// The one pair this user belongs to, plus createPair / acceptPair / revokePair.
    public let pairs: PairRepository

    // MARK: - Spot

    /// The pair's spots. Owns the ADDENDUM §K clamps in front of upsertSpot.
    public let spots: SpotRepository

    // MARK: - Trip

    /// The pair's live trip and its replies. Also owns the per-tripId setLowBattery latch
    /// (ADDENDUM §L) — nothing else in the app may call setLowBattery.
    public let trips: TripRepository

    // MARK: - Tracking

    /// The only thing this client writes (contract §"The one thing clients write").
    public let positionSink: PositionSink

    /// The only type in the app that touches CoreLocation. `AppViewModel` owns its lifecycle:
    /// `start(...)` after `startTrip`, `applyTrip(...)` from the trip listener, `stop()` on
    /// "I'm here"/"Cancel". Nothing else may call `CLLocationManager`.
    public let tracker: LocationTracker

    /// Decision D7 / ADDENDUM §F — the on-device ETA that makes the server skip routing.
    /// Swapped for `FakeEtaProvider` by `-HSFakeEta 900` so a headless drive is deterministic.
    public let etaProvider: EtaProviding

    /// `UIDevice.batteryLevel` is -1 on the Simulator, so the contract's "< 15 %" row is only
    /// reachable through this seam. `-HSFakeBatteryPct 9` swaps in `FakeBatteryProvider`.
    public let battery: BatteryProviding

    // MARK: - Push

    /// Notification permission, the FCM token round-trip, and the local test alert. The
    /// token half cannot work on a Simulator (no APNs key, no paid team) and is guarded so
    /// its failure never blocks anything — see the header of PushService.swift.
    public let push: PushService

    /// The single funnel every arriving alert passes through — the remote-notification
    /// callback, both `UNUserNotificationCenter` delegate callbacks and the `_debugPushes`
    /// bridge. Nothing else in the app may parse a userInfo dictionary.
    public let router: PushRouter

    /// The receiver's Lock Screen countdown. Driven from the trip stream by `ios7`'s
    /// `AppViewModel` (`liveActivity.sync(trip:myUid:partnerName:)` on every snapshot).
    public let liveActivity: LiveActivityController

    #if DEBUG
    /// CLIENT_CONTRACT_ADDENDUM.md, "Emulator contract" — the debug-only listener on
    /// `_debugPushes where toUid == me`. FCM cannot deliver from the emulator, so this is
    /// the only way the server's alert DECISIONS are observable on a Simulator. Started by
    /// `ios7` once a uid exists: `debugPushes.start(uid:)`. Absent from Release entirely.
    public let debugPushes: DebugPushBridge
    #endif

    private init() {
        // Locals first: a class initialiser may not read `self`'s stored properties until
        // every one of them is assigned, and the repositories below need two of them.
        let db = Firestore.firestore()
        let callables = Callables()
        self.db = db
        self.callables = callables
        let positionSink = FirestorePositionSink()
        // Launch-argument driven, resolved once at launch. Both factories are pure and are
        // asserted by BatteryProviderTests, so the flags cannot silently stop working.
        let etaProvider = EtaProviderFactory.resolve()
        let battery = BatteryProviderFactory.resolve()
        self.positionSink = positionSink
        self.etaProvider = etaProvider
        self.battery = battery
        self.tracker = LocationTracker(etaProvider: etaProvider, battery: battery, sink: positionSink)
        if EtaProviderFactory.isFaked() || BatteryProviderFactory.isFaked() {
            NSLog(
                "[HS][services] fakes active — eta:%@ battery:%@",
                EtaProviderFactory.isFaked() ? "fake" : "mapkit",
                BatteryProviderFactory.isFaked() ? "fake" : "device"
            )
        }
        self.auth = AuthRepository()
        self.pairs = PairRepository(db: db, callables: callables)
        self.spots = SpotRepository(db: db, callables: callables)
        self.trips = TripRepository(db: db, callables: callables)
        self.push = PushService(callables: callables)
        // Both are the process-wide singletons, not fresh instances: `AppDelegate` reaches
        // the router through `PushRouter.handle(userInfo:)` before any view exists, so a
        // second instance here would silently split the bus in two.
        self.router = PushRouter.shared
        self.liveActivity = LiveActivityController.shared
        #if DEBUG
        self.debugPushes = DebugPushBridge(db: db)
        #endif
        // A terminal push can land while the trip listener is detached (app backgrounded),
        // and the Lock Screen must not keep counting down to a pickup that already
        // happened. `sync(trip:…)` covers the foreground case on its own.
        let liveActivity = self.liveActivity
        self.router.onEndLiveActivity = { liveActivity.end() }
    }
}
