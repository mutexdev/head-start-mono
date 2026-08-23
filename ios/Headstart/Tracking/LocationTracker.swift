// ios/Headstart/Tracking/LocationTracker.swift
//
// THE ONLY TYPE IN THE APP THAT TOUCHES CORELOCATION.
//
// It decides nothing. Every decision is `TrackingPhaseController`'s (pure, unit-tested in
// TrackingPhaseControllerTests / TripGuardTests) and every write is `PositionUploader`'s
// (unit-tested in PositionUploaderTests). What is left here is wiring, and the three pieces of
// wiring that are easy to get wrong are called out below.
//
// 1. AUTHORIZATION IS `WhenInUse` AND NOTHING ELSE (decision D6, absolute).
//    The Always-authorization request is never made and the Always usage-description key is
//    not in Info.plist, so the system alert offers no "Allow all the time" row. (Both
//    identifiers are deliberately left unspelled here: a repo-wide grep for them is a
//    done-criterion, and a comment must not be what makes it fail.) Background tracking still
//    works for the whole trip because `UIBackgroundModes` contains `location` and we set
//    `allowsBackgroundLocationUpdates = true` — which must be set AFTER authorization is
//    granted, or CoreLocation throws at runtime.
//    `showsBackgroundLocationIndicator = true` is deliberate: the blue pill is the product's
//    honesty guarantee, not a bug to hide.
//
// 2. THE GEOFENCE IS A BACKUP WAKE-UP AND NOTHING ELSE.
//    CLIENT_CONTRACT.md: "Arrival is decided by the server. Clients may register a geofence at
//    spot.radiusM as a backup wake-up, but must not send an `arrived` push themselves."
//    On entry this file forces ONE high-accuracy fix so the server can see the driver inside
//    the radius and make the call itself. There is no `endTrip(reason: .arrived)` here, no
//    push, and no local "you have arrived" anything. Region monitoring only wakes a TERMINATED
//    app under `Always` authorization, which we never request — so this is a backup while the
//    app is alive with background updates running, i.e. exactly the trip window.
//
// 3. THE ETA IS ASKED FOR ON ACCEPTED FIXES ONLY.
//    `MKDirections.calculateETA` throttles. The upload filter already spaces accepted fixes by
//    ≥ 5 s (near) / ≥ 30 s (far), so binding the ETA call to the ACCEPT — not to the raw OS
//    callback, which can fire many times a second — is what keeps us inside the throttle.
//    That is why the ETA lookup lives in the serial `upload` consumer and not in `ingest`.
//
// Isolation: `@MainActor`. Every `CLLocationManagerDelegate` method is `nonisolated` with a
// `MainActor.assumeIsolated { … }` body — the manager is created on the main actor, so its
// callbacks are delivered on the main queue and the assumption always holds. This is the one
// sanctioned pattern for the delegate in this codebase; do not invent a second one.

import Foundation
import UIKit
import CoreLocation

@MainActor
public final class LocationTracker: NSObject, ObservableObject {

    // MARK: Published state (drives the "Sharing with …" chrome)

    @Published public private(set) var isTracking = false
    @Published public private(set) var phase: Phase = .far
    @Published public private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published public private(set) var pendingUploads = 0

    // MARK: Callbacks — both carry the trip id, on purpose

    /// Fired ONCE per trip, the first time the battery provider reports under 15 %
    /// (decision D3). The tripId is handed out so the owner cannot latch the wrong trip:
    /// `tracker.onLowBattery = { id in Task { await trips.reportLowBattery(tripId: id) } }`.
    /// `TripRepository.reportLowBattery` is the ONLY entry point to the `setLowBattery`
    /// callable (CLIENT_CONTRACT_ADDENDUM.md §L) — never call the callable from here.
    public var onLowBattery: ((String) -> Void)?

    /// The local three-hour guard fired (CLIENT_CONTRACT.md §Stop tracking). Tracking has
    /// already stopped by the time this is called; the owner still has to `endTrip`.
    public var onGuardExpired: ((String) -> Void)?

    // MARK: Collaborators

    private let manager: CLLocationManager
    private let etaProvider: EtaProviding
    private let battery: BatteryProviding
    private let sink: PositionSink

    // MARK: Per-trip state

    private var controller: TrackingPhaseController?
    private var uploader: PositionUploader?
    private var tripId: String?
    private var spot: TripSpot?
    private var pipeline: AsyncStream<LocationFix>.Continuation?
    private var pipelineTask: Task<Void, Never>?
    private var batteryObserver: Bool = false
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var oneShotContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    static let geofenceIdentifier = "headstart.destination"

    public init(
        etaProvider: EtaProviding = MapKitEtaProvider(),
        battery: BatteryProviding = DeviceBatteryProvider(),
        sink: PositionSink,
        manager: CLLocationManager = CLLocationManager()
    ) {
        self.etaProvider = etaProvider
        self.battery = battery
        self.sink = sink
        self.manager = manager
        super.init()
        // Read through `self` only after `super.init()` — a stored property may not be read
        // before the superclass initialiser has run.
        self.authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .automotiveNavigation
    }

    // MARK: - Authorization

    public var hasLocationPermission: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// When In Use ONLY — decision D6. Returns once the person has answered, or immediately if
    /// they already have. There is deliberately no Always-authorization counterpart anywhere
    /// in this type, and adding one would break decision D6.
    @discardableResult
    public func requestWhenInUseAuthorization() async -> CLAuthorizationStatus {
        if authorizationStatus != .notDetermined { return authorizationStatus }
        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    /// One high-accuracy fix, for `startTrip` and for centring the spot editor's map.
    /// nil when permission is missing or the OS gives up.
    public func currentCoordinate() async -> CLLocationCoordinate2D? {
        guard hasLocationPermission else { return nil }
        if let cached = manager.location, cached.timestamp.timeIntervalSinceNow > -30 {
            return cached.coordinate
        }
        return await withCheckedContinuation { continuation in
            oneShotContinuation = continuation
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.requestLocation()
        }
    }

    // MARK: - Trip lifecycle

    /// Starts tracking a trip `startTrip` has just created — or one it reported as
    /// `existing: true`, which is the same thing from this file's point of view: it attaches
    /// to whatever trip id it is given and starts streaming.
    public func start(tripId: String, spot: TripSpot, nearBandM: Double, startedAtMs: Int64) {
        guard hasLocationPermission else {
            NSLog("[HS][track] start refused: no location permission")
            return
        }
        stop()   // never run two trips at once

        let controller = TrackingPhaseController(
            spotLat: spot.lat,
            spotLng: spot.lng,
            nearBandM: nearBandM,
            startedAtMs: startedAtMs
        )
        let uploader = PositionUploader(tripId: tripId, sink: sink)

        self.controller = controller
        self.uploader = uploader
        self.tripId = tripId
        self.spot = spot
        self.phase = .far
        self.isTracking = true

        // One serial consumer, so uploads keep their order even though each one waits on an
        // ETA round-trip first (decision D8: AsyncStream, never Combine).
        let (stream, continuation) = AsyncStream<LocationFix>.makeStream()
        pipeline = continuation
        pipelineTask = Task { [weak self] in
            for await fix in stream {
                guard let self else { return }
                await self.upload(fix)
            }
        }

        applyParameters(controller.params())
        // Safe here and nowhere earlier: `hasLocationPermission` is already true, and
        // `UIBackgroundModes` contains `location`.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()

        startBatteryMonitoring()
        startDestinationGeofence(spot: spot)
        NSLog("[HS][track] started trip %@ near=%.0fm", tripId, nearBandM)
    }

    /// Fed from the single trip listener. Applies `phaseHint` and STOPS TRACKING the moment
    /// the document leaves `driving` (CLIENT_CONTRACT.md §Stop tracking) — including when the
    /// server ends the trip itself as `arrived`, `lost` or `timeout`.
    public func applyTrip(_ trip: Trip?) {
        guard isTracking else { return }
        guard let trip, trip.id == tripId, trip.state == .driving else {
            NSLog("[HS][track] stopping: trip no longer driving")
            stop()
            return
        }
        controller?.onServerPhaseHint(trip.phaseHint)
        if let controller {
            phase = controller.phase
            applyParameters(controller.params())
        }
    }

    /// The local "I'm here" / "Cancel" path: stop immediately, do not wait for the listener.
    public func stop() {
        guard isTracking || pipelineTask != nil else { return }
        manager.stopUpdatingLocation()
        if manager.allowsBackgroundLocationUpdates {
            manager.allowsBackgroundLocationUpdates = false
        }
        stopDestinationGeofence()
        stopBatteryMonitoring()
        pipeline?.finish()
        pipeline = nil
        pipelineTask?.cancel()
        pipelineTask = nil
        controller = nil
        uploader = nil
        tripId = nil
        spot = nil
        isTracking = false
        phase = .far
        pendingUploads = 0
    }

    // MARK: - Fix handling

    func ingest(_ fixes: [LocationFix]) {
        guard let controller, let tripId else { return }

        // The three-hour guard is local and outranks everything the server says.
        if controller.shouldStop(nowMs: nowMs()) {
            NSLog("[HS][track] 3-hour guard fired for trip %@", tripId)
            stop()
            onGuardExpired?(tripId)
            return
        }

        // Polled here as well as on the OS notification, because a fake provider never posts
        // one and a real device only posts on a 1 % change.
        checkBattery()

        for fix in fixes {
            switch controller.onFix(fix) {
            case .upload(let accepted, let newPhase):
                if newPhase != phase {
                    phase = newPhase
                    applyParameters(controller.params())
                }
                pipeline?.yield(accepted)
            case .skip:
                continue
            }
        }
    }

    private func upload(_ fix: LocationFix) async {
        guard let uploader, let spot else { return }
        // ACCEPTED fixes only — see note 3 in this file's header.
        let etaSec = await etaProvider.etaSeconds(
            fromLat: fix.lat, fromLng: fix.lng,
            toLat: spot.lat, toLng: spot.lng
        )
        await uploader.submit(PositionUpload(fix: fix, etaSec: etaSec))
        pendingUploads = await uploader.pending
    }

    private func applyParameters(_ params: LocationParams) {
        manager.desiredAccuracy = params.priority == .high
            ? kCLLocationAccuracyBestForNavigation
            : kCLLocationAccuracyHundredMeters
        manager.distanceFilter = params.minDisplacementM
    }

    // MARK: - Battery (CLIENT_CONTRACT.md §Battery, decisions D2/D3)

    private func startBatteryMonitoring() {
        battery.startMonitoring()
        if !batteryObserver {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(batteryLevelChanged),
                name: UIDevice.batteryLevelDidChangeNotification,
                object: nil
            )
            batteryObserver = true
        }
        checkBattery()
    }

    private func stopBatteryMonitoring() {
        if batteryObserver {
            NotificationCenter.default.removeObserver(
                self,
                name: UIDevice.batteryLevelDidChangeNotification,
                object: nil
            )
            batteryObserver = false
        }
        battery.stopMonitoring()
    }

    @objc private nonisolated func batteryLevelChanged() {
        Task { @MainActor [weak self] in self?.checkBattery() }
    }

    /// The one-shot in `TrackingPhaseController.onBatteryPercent` returns true exactly once
    /// per trip, so `onLowBattery` fires exactly once per trip. Re-applying the parameters
    /// afterwards is what moves `far` onto the 60 s / 400 m row; D2 keeps `near` untouched
    /// because `params()` checks the phase first.
    private func checkBattery() {
        guard let controller, let tripId, let percent = battery.percent else { return }
        if controller.onBatteryPercent(percent) {
            NSLog("[HS][track] battery %d%% — low-battery cadence for trip %@", percent, tripId)
            onLowBattery?(tripId)
            applyParameters(controller.params())
        }
    }

    // MARK: - Destination geofence (BACKUP WAKE-UP ONLY — see note 2 in the header)

    private func startDestinationGeofence(spot: TripSpot) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: spot.lat, longitude: spot.lng),
            radius: SpotLimits.clampRadiusM(spot.radiusM),
            identifier: Self.geofenceIdentifier
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false
        manager.startMonitoring(for: region)
    }

    private func stopDestinationGeofence() {
        for region in manager.monitoredRegions where region.identifier == Self.geofenceIdentifier {
            manager.stopMonitoring(for: region)
        }
    }

    func onGeofenceEntered(_ identifier: String) {
        guard identifier == Self.geofenceIdentifier, isTracking else { return }
        // Force ONE high-accuracy fix so the SERVER sees the driver inside the radius and makes
        // the arrival decision. The client never claims arrival — no endTrip, no push, no
        // local "arrived" state. That is CLIENT_CONTRACT.md, not a style preference.
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.requestLocation()
    }

    // MARK: - Delegate plumbing, called from the nonisolated extension below

    func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        if status != .notDetermined, let continuation = authorizationContinuation {
            authorizationContinuation = nil
            continuation.resume(returning: status)
        }
    }

    func handleLocations(_ fixes: [LocationFix], last: CLLocationCoordinate2D?) {
        if let continuation = oneShotContinuation {
            oneShotContinuation = nil
            continuation.resume(returning: last)
        }
        ingest(fixes)
    }

    func handleFailure(_ description: String) {
        NSLog("[HS][track] location error: %@", description)
        if let continuation = oneShotContinuation {
            oneShotContinuation = nil
            continuation.resume(returning: nil)
        }
    }
}

// MARK: - CLLocationManagerDelegate
//
// `CLLocationManagerDelegate` is not main-actor annotated, so every method here is
// `nonisolated`. The manager was created on the main actor, so CoreLocation delivers its
// callbacks on the main queue and `MainActor.assumeIsolated` is sound — it is an assertion of
// something CoreLocation guarantees, not a hope. Non-Sendable `CLLocation`s are converted to
// `LocationFix` values BEFORE the hop, so nothing unsafe crosses.

extension LocationTracker: CLLocationManagerDelegate {

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { self.handleAuthorizationChange(status) }
    }

    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let fixes: [LocationFix] = locations.map { location in
            LocationFix(
                lat: location.coordinate.latitude,
                lng: location.coordinate.longitude,
                // A negative horizontalAccuracy means the fix is invalid. Make it fail the
                // 100 m accuracy gate rather than sneak through as a perfect "0 m".
                accuracyM: location.horizontalAccuracy < 0 ? 9_999 : location.horizontalAccuracy,
                speedMps: location.speed,
                tsMs: Int64(location.timestamp.timeIntervalSince1970 * 1000)
            )
        }
        let last = locations.last?.coordinate
        MainActor.assumeIsolated { self.handleLocations(fixes, last: last) }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let identifier = region.identifier
        MainActor.assumeIsolated { self.onGeofenceEntered(identifier) }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let description = error.localizedDescription
        MainActor.assumeIsolated { self.handleFailure(description) }
    }

    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        // A failed geofence is survivable: it is a backup, and the uploads are the real
        // mechanism. Log it and carry on rather than tearing the trip down.
        let description = error.localizedDescription
        MainActor.assumeIsolated { self.handleFailure("geofence: \(description)") }
    }
}
