// ios/Headstart/UI/AppViewModel.swift
//
// The single owner of app state. Every screen written before this batch is stateless: it
// receives plain values and closures and knows nothing about Firestore, callables or the
// tracker. This is the one object that mirrors every repository stream, runs every action,
// and fans the live trip out to the tracker and the Live Activity.
//
// FIVE WIRING RULES THIS FILE IS THE SOLE ENFORCER OF (handed down from ios6):
//
//  1. `push.requestAuthorization()` is called once, from `completeProfile`. Until it is
//     granted, `willPresent`/`didReceive` never fire and only the `content-available`
//     funnel works.
//  2. `push.setDisplayName(_:)` runs BEFORE `push.registerCurrentToken()`, so
//     `registerPushToken({token, platform, displayName?})` carries the name and the server
//     can denormalise it into `pairs/{id}.memberNames` (ADDENDUM §M). These are the ONLY
//     two call sites for token registration in the app.
//  3. `liveActivity.sync(trip:myUid:partnerName:)` runs on EVERY trip snapshot. That one
//     call starts, updates and ends the Activity; `end()` is never called anywhere else
//     except sign-out. The controller no-ops for the driver (it checks `receiverUid`).
//  4. `#if DEBUG debugPushes.start(uid:)` after sign-in, `stop()` on sign-out. Required by
//     CLIENT_CONTRACT_ADDENDUM.md — it is the only way the server's alert DECISIONS are
//     observable on a Simulator.
//  5. Nothing here parses a userInfo dictionary. `PushRouter.handle(userInfo:)` is the only
//     entry point; this object reads the already-decided `router.destination`.
//
// Isolation: `@MainActor`, like every repository. All mirroring is `for await … in` over
// the repositories' `@Published` projections — decision D8, AsyncStream/AsyncPublisher and
// never a Combine `sink`.

import Foundation
import SwiftUI
import CoreLocation

@MainActor
public final class AppViewModel: ObservableObject {

    /// The route state machine `RootView` switches on. Ordered by how far through
    /// onboarding the user is; `loading` only ever appears between a sign-in and the first
    /// `pairs` snapshot, which is why it sits between signed-out and paired rather than at
    /// the top.
    public enum Stage: Equatable, Sendable {
        case loading
        case signedOut
        case needsProfile
        case needsPair
        case main
    }

    /// UserDefaults key for the display name. Deliberately NOT `@AppStorage`: that property
    /// wrapper is a `DynamicProperty` and only republishes inside a `View`. In an
    /// `ObservableObject` it silently fails to fire `objectWillChange`, and `stage` depends
    /// on this value — the app would sit on the profile screen after saving a name.
    public static let displayNameKey = "headstart.displayName"

    // MARK: - Published state (everything a screen can render)

    @Published public private(set) var uid: String?
    @Published public private(set) var displayName: String = ""
    @Published public private(set) var pair: Pair?
    @Published public private(set) var spots: [Spot] = []
    @Published public private(set) var activeTrip: Trip?
    @Published public private(set) var replies: [Reply] = []
    @Published public private(set) var hasLoadedPair = false

    /// Transient UI state that outlives a single screen (the pairing flow spans two).
    @Published public var errorText: String?
    @Published public var inviteCode: String?

    private let services: ServiceLocator
    private let router: PushRouter
    private let defaults: UserDefaults
    private var mirrorTasks: [Task<Void, Never>] = []

    public init(
        services: ServiceLocator = .shared,
        router: PushRouter = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.services = services
        self.router = router
        self.defaults = defaults
        self.uid = services.auth.uid
        self.displayName = Self.storedDisplayName(
            defaults: defaults,
            authName: services.auth.displayName
        )

        // Both callbacks carry the tripId so neither can latch the wrong trip.
        services.tracker.onLowBattery = { [weak self] tripId in
            guard let self else { return }
            Task { await self.services.trips.reportLowBattery(tripId: tripId) }
        }
        services.tracker.onGuardExpired = { [weak self] tripId in
            guard let self else { return }
            Task { await self.end(tripId: tripId, reason: .cancelled) }
        }

        startMirroring()
        // A relaunch with a live session must re-attach every listener; `startMirroring`
        // only reacts to CHANGES of `auth.uid`, and there is none at launch.
        if let uid, !uid.isEmpty { attachSession(uid: uid) }
    }

    // MARK: - Derived values screens read

    /// Already resolved through `PartnerName.resolve(pair:selfUid:)` — the same string
    /// every screen and the Live Activity get, never nil, "Your partner" as the fallback.
    public var partnerName: String {
        guard let uid else { return PartnerName.fallback }
        return PartnerName.resolve(pair: pair, selfUid: uid)
    }

    public var stage: Stage {
        guard let uid, !uid.isEmpty else { return .signedOut }
        if displayName.isEmpty { return .needsProfile }
        if !hasLoadedPair { return .loading }
        guard let pair, pair.isActive else { return .needsPair }
        return .main
    }

    /// The trip screens take over only for a `driving` trip; an `armed` trip is a banner on
    /// Home instead.
    public var drivingTrip: Trip? {
        guard let activeTrip, activeTrip.state == .driving else { return nil }
        return activeTrip
    }

    public var armedTrip: Trip? {
        guard let activeTrip, activeTrip.state == .armed else { return nil }
        return activeTrip
    }

    public var myRoleInTrip: TripRole? {
        guard let uid, let activeTrip else { return nil }
        return activeTrip.role(for: uid)
    }

    /// "Your usual spot" — the receiver's home card and the driver's big green card.
    public var primarySpot: Spot? { spots.first }

    public var latestReplyFromPartner: Reply? {
        guard let uid else { return nil }
        return replies.last { $0.fromUid != uid }
    }

    // MARK: - Mirroring
    //
    // One task per repository stream. `@Published`'s `.values` is an `AsyncPublisher`, so
    // this is the same AsyncSequence discipline the Firestore listeners use (D8), and each
    // loop runs on the main actor because the enclosing type is `@MainActor`.

    private func startMirroring() {
        mirrorTasks.append(Task { [weak self] in
            guard let self else { return }
            for await uid in self.services.auth.$uid.values {
                self.onSessionChanged(uid: uid)
            }
        })
        mirrorTasks.append(Task { [weak self] in
            guard let self else { return }
            for await pair in self.services.pairs.$pair.values {
                self.pair = pair
                self.hasLoadedPair = self.services.pairs.hasLoaded
                self.onPairChanged(pair)
            }
        })
        mirrorTasks.append(Task { [weak self] in
            guard let self else { return }
            for await spots in self.services.spots.$spots.values {
                self.spots = spots
            }
        })
        mirrorTasks.append(Task { [weak self] in
            guard let self else { return }
            for await trip in self.services.trips.$activeTrip.values {
                self.activeTrip = trip
                self.onTripChanged(trip)
            }
        })
        mirrorTasks.append(Task { [weak self] in
            guard let self else { return }
            for await replies in self.services.trips.$replies.values {
                self.replies = replies
            }
        })
    }

    private func onSessionChanged(uid newUid: String?) {
        let previous = uid
        uid = newUid
        guard let newUid, !newUid.isEmpty else {
            detachSession()
            return
        }
        guard newUid != previous else { return }
        if displayName.isEmpty, let authName = services.auth.displayName, !authName.isEmpty {
            setDisplayName(authName)
        }
        attachSession(uid: newUid)
    }

    /// Everything that must happen exactly once per signed-in session, in the order ios6's
    /// handoff fixes: name first, then permission, then the token, then the debug bridge.
    private func attachSession(uid: String) {
        services.pairs.observe(uid: uid)
        services.push.setDisplayName(displayName.isEmpty ? nil : displayName)
        #if DEBUG
        // Rows written before this call are backlog, not news — start it before anything
        // is triggered, which is why it is here and not after the awaits below.
        services.debugPushes.start(uid: uid)
        #endif
        Task { [services] in
            await services.push.registerCurrentToken()
        }
    }

    private func detachSession() {
        services.pairs.stop()
        services.spots.stop()
        services.trips.stop()
        services.tracker.stop()
        services.liveActivity.end()
        #if DEBUG
        services.debugPushes.stop()
        #endif
        pair = nil
        spots = []
        activeTrip = nil
        replies = []
        hasLoadedPair = false
        inviteCode = nil
    }

    private func onPairChanged(_ pair: Pair?) {
        guard let pair, pair.isActive else {
            services.spots.stop()
            services.trips.stop()
            return
        }
        services.spots.observe(pairId: pair.id)
        services.trips.observe(pairId: pair.id)
    }

    private func onTripChanged(_ trip: Trip?) {
        // Tracking: only the driver of a `driving` trip tracks, and it stops the moment the
        // document leaves `driving` (CLIENT_CONTRACT.md §"Stop tracking").
        if let uid, let trip, trip.state == .driving, trip.driverUid == uid {
            services.tracker.applyTrip(trip)
        } else {
            services.tracker.stop()
        }
        // Live Activity: EVERY snapshot, receiver side only. This single call starts,
        // updates and ends it.
        if let uid {
            services.liveActivity.sync(trip: trip, myUid: uid, partnerName: partnerName)
        }
    }

    // MARK: - Onboarding

    public func sendCode(to e164: String) async -> String? {
        do {
            try await services.auth.sendCode(to: e164)
            return nil
        } catch {
            return error.asHeadstartError().userMessage
        }
    }

    public func resendCode() async {
        try? await services.auth.resendCode()
    }

    public var pendingNumber: String? { services.auth.pendingNumber }

    public func verify(code: String) async -> String? {
        do {
            try await services.auth.verify(code: code)
            onSessionChanged(uid: services.auth.uid)
            return nil
        } catch {
            return error.asHeadstartError().userMessage
        }
    }

    /// Profile's "Allow and continue": save the name, ask the two permissions in the order
    /// that matters, then register the push token WITH the name attached.
    @discardableResult
    public func completeProfile(name: String) async -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return HeadstartError.badName.userMessage }
        do {
            try await services.auth.setDisplayName(trimmed)
        } catch {
            // The Auth profile write is a nicety; the copy that the OTHER person reads
            // comes from `registerPushToken({displayName})` below. Losing it must not trap
            // the user on the profile screen forever.
            NSLog("[HS][profile] setDisplayName failed: \(error.asHeadstartError().code)")
        }
        setDisplayName(trimmed)
        services.push.setDisplayName(trimmed)
        await Permissions.requestOnboarding(push: services.push, tracker: services.tracker)
        await services.push.registerCurrentToken()
        return nil
    }

    private func setDisplayName(_ name: String) {
        displayName = name
        defaults.set(name, forKey: Self.displayNameKey)
    }

    private static func storedDisplayName(defaults: UserDefaults, authName: String?) -> String {
        let stored = (defaults.string(forKey: displayNameKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty { return stored }
        return (authName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Pairing

    public func createInvite() async {
        do {
            inviteCode = try await services.pairs.create().inviteCode
            errorText = nil
        } catch {
            inviteCode = nil
            errorText = error.asHeadstartError().userMessage
        }
    }

    public func acceptInvite(code: String) async -> String? {
        do {
            try await services.pairs.accept(code: code)
            return nil
        } catch {
            return error.asHeadstartError().userMessage
        }
    }

    public func unpair() async -> String? {
        do {
            try await services.pairs.revoke()
            inviteCode = nil
            return nil
        } catch {
            return error.asHeadstartError().userMessage
        }
    }

    // MARK: - Spots

    public func saveSpot(existing: Spot?, draft: SpotDraft) async -> String? {
        guard let pairId = pair?.id else { return HeadstartError.notPaired.userMessage }
        do {
            try await services.spots.upsert(
                pairId: pairId,
                name: draft.name,
                lat: draft.lat,
                lng: draft.lng,
                leadTimeMin: draft.leadTimeMin,
                radiusM: draft.radiusM,
                spotId: existing?.id
            )
            return nil
        } catch {
            return error.asHeadstartError().userMessage
        }
    }

    public func deleteSpot(_ spot: Spot) async -> String? {
        do {
            try await services.spots.delete(spotId: spot.id)
            return nil
        } catch {
            return error.asHeadstartError().userMessage
        }
    }

    /// The receiver's +/- stepper on ReceiverHome. Writes straight through `upsertSpot`;
    /// `SpotRepository` clamps to the contract's 1–30 (ADDENDUM §K).
    public func setLeadTime(_ minutes: Int, on spot: Spot) async -> String? {
        await saveSpot(
            existing: spot,
            draft: SpotDraft(
                name: spot.name,
                lat: spot.lat,
                lng: spot.lng,
                leadTimeMin: minutes,
                radiusM: spot.radiusM
            )
        )
    }

    // MARK: - Trips

    /// The one-tap driver flow: one fix, the on-device ETA (decision D7 / ADDENDUM §F —
    /// this is what makes an iOS trip cost the server ZERO routing calls), `startTrip`,
    /// then tracking with the bands the server returned.
    ///
    /// ADDENDUM §E — when the server answers `existing: true` a trip was already running.
    /// The client ATTACHES: it must not restart a tracker that is already streaming.
    @discardableResult
    public func startTrip(to spot: Spot) async -> String? {
        errorText = nil
        guard let coordinate = await services.tracker.currentCoordinate() else {
            let message = "We couldn't get your location. Check that Headstart has location access."
            errorText = message
            return message
        }
        // The resolved provider, not `MapKitEtaProvider()` directly: `-HSFakeEta 900` swaps
        // in `FakeEtaProvider` and a headless drive needs that to reach the wire.
        let etaSec = await services.etaProvider.etaSeconds(
            fromLat: coordinate.latitude,
            fromLng: coordinate.longitude,
            toLat: spot.lat,
            toLng: spot.lng
        )
        do {
            let response = try await services.trips.startTrip(
                spotId: spot.id,
                lat: coordinate.latitude,
                lng: coordinate.longitude,
                // Read straight off `PrivacySettings` — Settings owns that key and a second
                // hand-typed literal here is how the two silently diverge.
                fuzzy: PrivacySettings.hideExactPosition,
                etaSec: etaSec
            )
            NSLog(
                "[HS][trip] startTrip tripId=%@ existing=%@ etaSec=%@ near=%@",
                response.tripId,
                response.existing ? "true" : "false",
                etaSec.map(String.init) ?? "-",
                response.bands.map { String(Int($0.near)) } ?? "-"
            )
            if response.existing, services.tracker.isTracking {
                return nil   // already attached; do not restart
            }
            services.tracker.start(
                tripId: response.tripId,
                spot: TripSpot(
                    lat: spot.lat, lng: spot.lng, radiusM: spot.radiusM, name: spot.name
                ),
                nearBandM: response.bands?.near ?? spot.radiusM,
                startedAtMs: Int64(Date().timeIntervalSince1970 * 1000)
            )
            return nil
        } catch {
            let message = error.asHeadstartError().userMessage
            errorText = message
            return message
        }
    }

    /// The receiver's "Ping me when they leave".
    public func armTrip(to spot: Spot) async -> String? {
        do {
            try await services.trips.armTrip(spotId: spot.id)
            errorText = nil
            return nil
        } catch {
            let message = error.asHeadstartError().userMessage
            errorText = message
            return message
        }
    }

    public func endTrip(reason: EndTripReason) async -> String? {
        guard let trip = activeTrip else { return nil }
        return await end(tripId: trip.id, reason: reason)
    }

    @discardableResult
    private func end(tripId: String, reason: EndTripReason) async -> String? {
        // Stop locally first: the contract's "stop tracking" is the local tap, not the
        // round trip, and a failed callable must not leave the GPS running.
        services.tracker.stop()
        do {
            try await services.trips.endTrip(tripId: tripId, reason: reason)
            errorText = nil
            return nil
        } catch {
            let message = error.asHeadstartError().userMessage
            errorText = message
            return message
        }
    }

    public func runningLate(extraMin: Int) async -> String? {
        guard let trip = activeTrip else { return nil }
        do {
            try await services.trips.setRunningLate(tripId: trip.id, extraMin: extraMin)
            errorText = nil
            return nil
        } catch {
            return error.asHeadstartError().userMessage
        }
    }

    public func sendReply(kind: ReplyKind, text: String?) async -> String? {
        guard let trip = activeTrip else { return nil }
        do {
            try await services.trips.sendReply(tripId: trip.id, kind: kind, text: text)
            errorText = nil
            return nil
        } catch {
            return error.asHeadstartError().userMessage
        }
    }

    // MARK: - Settings

    public func sendTestAlert() async -> String? {
        do {
            try await services.push.sendTestAlert()
            return nil
        } catch {
            return "We couldn't schedule the test alert. Check notification permission in iOS Settings."
        }
    }

    public func signOut() {
        services.tracker.stop()
        services.liveActivity.end()
        try? services.auth.signOut()
        defaults.removeObject(forKey: Self.displayNameKey)
        displayName = ""
        uid = nil
        detachSession()
    }

    /// Where the spot editor opens its map when adding a new spot. The fallback is the
    /// Dhaka coordinate the plan's drive route ends at, so a simulator with no fix still
    /// lands somewhere sensible instead of at (0, 0) in the Gulf of Guinea.
    #if DEBUG
    /// Test seam for `E2EAutopilot` only — `services` is private and the harness needs to
    /// know whether CoreLocation has produced a usable fix before it taps "I'm coming".
    func currentCoordinateForHarness() async -> CLLocationCoordinate2D? {
        await services.tracker.currentCoordinate()
    }
    #endif

    public func startCoordinate() async -> CLLocationCoordinate2D {
        await services.tracker.currentCoordinate()
            ?? CLLocationCoordinate2D(latitude: 23.7806, longitude: 90.4193)
    }
}
