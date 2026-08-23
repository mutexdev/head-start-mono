// ios/HeadstartTests/BatteryProviderTests.swift
//
// `UIDevice.current.batteryLevel` is -1 on the Simulator, forever, whether or not monitoring is
// enabled. Without a seam, three contract rules would be unreachable by any test on this
// machine and would ship as dead code:
//
//   * the "far + battery < 15 % → balanced / 60 s / 400 m" row of CLIENT_CONTRACT.md's
//     parameters table
//   * "call setLowBattery({lowBattery:true}) once per trip" (decision D3, ADDENDUM §L)
//   * decision D2 — low battery must never downgrade the `near` cadence
//
// This file drives all three through `FakeBatteryProvider`, and pins the launch-argument
// contract (`-HSFakeBatteryPct`, `-HSFakeEta`) that `ServiceLocator` depends on, so a later
// batch's headless drive cannot silently lose its fakes.
//
// It also asserts the premise itself: `DeviceBatteryProvider.percent` really is nil here. If
// that assertion ever fails, the Simulator gained a battery and this whole seam can be
// reconsidered.

import XCTest
@testable import Headstart

private func suite(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

// MARK: - The providers themselves

final class BatteryProviderTests: XCTestCase {

    @MainActor
    func testTheFakeReportsExactlyWhatItWasBuiltWith() {
        XCTAssertEqual(FakeBatteryProvider(percent: 9).percent, 9)
        XCTAssertEqual(FakeBatteryProvider(percent: 0).percent, 0)
        XCTAssertEqual(FakeBatteryProvider(percent: 100).percent, 100)
    }

    @MainActor
    func testTheFakeCanReproduceTheSimulatorsNoAnswer() {
        XCTAssertNil(FakeBatteryProvider(percent: nil).percent)
    }

    /// The reason this file exists. `batteryLevel` is -1 on the Simulator, and
    /// `DeviceBatteryProvider` must translate that to nil rather than to 0 % — a 0 % reading
    /// would latch low battery on the first fix of every simulator drive.
    @MainActor
    func testTheDeviceProviderReportsNothingOnTheSimulator() {
        let provider = DeviceBatteryProvider()
        provider.startMonitoring()
        defer { provider.stopMonitoring() }
        #if targetEnvironment(simulator)
        XCTAssertNil(provider.percent, "the Simulator gained a battery — revisit this seam")
        #else
        if let percent = provider.percent {
            XCTAssertTrue((0...100).contains(percent))
        }
        #endif
    }
}

// MARK: - The launch-argument contract

/// `xcrun simctl launch <udid> com.mutexdev.headstart -HSFakeBatteryPct 9 -HSFakeEta 900`.
/// `UserDefaults` parses `-key value` launch arguments itself, so these factories read a
/// `UserDefaults` and nothing else — which is exactly what makes them testable.
final class LaunchArgumentProviderTests: XCTestCase {

    func testWithNoArgumentTheRealBatteryProviderIsUsed() {
        let defaults = suite("hs.battery.absent")
        // A double optional: outer nil means "no launch argument". XCTAssertNil would coerce
        // it to Any? and warn, so compare explicitly.
        XCTAssertTrue(BatteryProviderFactory.fakePercent(defaults: defaults) == nil)
        XCTAssertFalse(BatteryProviderFactory.isFaked(defaults: defaults))
        XCTAssertTrue(BatteryProviderFactory.resolve(defaults: defaults) is DeviceBatteryProvider)
    }

    @MainActor
    func testFakeBatteryPctNineProducesAPhoneAtNinePercent() {
        let defaults = suite("hs.battery.nine")
        defaults.set(9, forKey: BatteryProviderFactory.launchArgumentKey)
        XCTAssertTrue(BatteryProviderFactory.isFaked(defaults: defaults))
        let provider = BatteryProviderFactory.resolve(defaults: defaults)
        XCTAssertTrue(provider is FakeBatteryProvider)
        XCTAssertEqual(provider.percent, 9)
    }

    @MainActor
    func testAHealthyFakePercentNeverTripsTheLowBatteryRow() {
        let defaults = suite("hs.battery.eighty")
        defaults.set(80, forKey: BatteryProviderFactory.launchArgumentKey)
        let provider = BatteryProviderFactory.resolve(defaults: defaults)
        XCTAssertEqual(provider.percent, 80)
        let c = TrackingPhaseController(spotLat: 0, spotLng: 0, nearBandM: 3_850, startedAtMs: 0)
        XCTAssertFalse(c.onBatteryPercent(provider.percent!))
        XCTAssertFalse(c.lowBattery)
    }

    @MainActor
    func testANegativeFakePercentReproducesAnUnknownReading() {
        let defaults = suite("hs.battery.negative")
        defaults.set(-1, forKey: BatteryProviderFactory.launchArgumentKey)
        XCTAssertTrue(BatteryProviderFactory.isFaked(defaults: defaults))
        XCTAssertNil(BatteryProviderFactory.resolve(defaults: defaults).percent)
    }

    @MainActor
    func testAnAbsurdFakePercentIsClampedToOneHundred() {
        let defaults = suite("hs.battery.absurd")
        defaults.set(400, forKey: BatteryProviderFactory.launchArgumentKey)
        XCTAssertEqual(BatteryProviderFactory.resolve(defaults: defaults).percent, 100)
    }

    func testWithNoArgumentTheRealMapKitEtaProviderIsUsed() {
        let defaults = suite("hs.eta.absent")
        XCTAssertTrue(EtaProviderFactory.fakeSeconds(defaults: defaults) == nil)
        XCTAssertFalse(EtaProviderFactory.isFaked(defaults: defaults))
        XCTAssertTrue(EtaProviderFactory.resolve(defaults: defaults) is MapKitEtaProvider)
    }

    func testFakeEtaNineHundredAlwaysAnswersNineHundred() async {
        let defaults = suite("hs.eta.900")
        defaults.set(900, forKey: EtaProviderFactory.launchArgumentKey)
        XCTAssertTrue(EtaProviderFactory.isFaked(defaults: defaults))
        let provider = EtaProviderFactory.resolve(defaults: defaults)
        XCTAssertTrue(provider is FakeEtaProvider)
        let a = await provider.etaSeconds(fromLat: 23.78, fromLng: 90.41, toLat: 23.75, toLng: 90.39)
        let b = await provider.etaSeconds(fromLat: 0, fromLng: 0, toLat: 1, toLng: 1)
        XCTAssertEqual(a, 900)
        XCTAssertEqual(b, 900, "the fake must be deterministic regardless of the coordinates")
    }

    /// `-HSFakeEta 0` is how the "MapKit is permanently down" branch is driven: the position
    /// document must then omit `etaSec` entirely (ADDENDUM §J — writing NSNull would be an
    /// eighth key and the rules reject it).
    func testFakeEtaZeroMeansNoEtaAtAll() async {
        let defaults = suite("hs.eta.zero")
        defaults.set(0, forKey: EtaProviderFactory.launchArgumentKey)
        XCTAssertTrue(EtaProviderFactory.isFaked(defaults: defaults))
        let provider = EtaProviderFactory.resolve(defaults: defaults)
        let seconds = await provider.etaSeconds(fromLat: 23.78, fromLng: 90.41, toLat: 23.75, toLng: 90.39)
        XCTAssertNil(seconds)
        let upload = PositionUpload(
            fix: LocationFix(lat: 23.78, lng: 90.41, accuracyM: 8, speedMps: 11, tsMs: 1),
            etaSec: seconds
        )
        XCTAssertFalse(FirestorePositionSink.documentFields(for: upload).keys.contains("etaSec"))
    }
}

// MARK: - D3, the once-per-trip latch, driven through the fake

final class LowBatteryLatchTests: XCTestCase {

    private func controller() -> TrackingPhaseController {
        TrackingPhaseController(spotLat: 0, spotLng: 0, nearBandM: 3_850, startedAtMs: 0)
    }

    /// The whole of decision D3 in one test: the transition into low battery is reported
    /// exactly once, no matter how many times the provider is polled. `LocationTracker` polls
    /// on every fix AND on every `batteryLevelDidChange`, so "many times" is the normal case,
    /// not an edge case.
    @MainActor
    func testTheLowBatteryTransitionIsReportedExactlyOncePerTrip() {
        let provider = FakeBatteryProvider(percent: 9)
        let c = controller()
        var fired = 0
        for _ in 0..<200 where c.onBatteryPercent(provider.percent!) { fired += 1 }
        XCTAssertEqual(fired, 1)
        XCTAssertTrue(c.lowBattery)
    }

    /// A NEW trip means a new controller, so the latch starts clear again — "once per trip",
    /// not "once per install". The server-side half of that (the tripId-keyed set in
    /// TripRepository) is what stops a retry storm; this is the client-side half.
    @MainActor
    func testANewTripStartsWithTheLatchClear() {
        let provider = FakeBatteryProvider(percent: 9)
        let first = controller()
        XCTAssertTrue(first.onBatteryPercent(provider.percent!))
        let second = controller()
        XCTAssertTrue(second.onBatteryPercent(provider.percent!), "a new trip re-arms the latch")
    }

    /// Fifteen per cent is not "< 15 %". The boundary is pinned because Android must round it
    /// identically or the two phones would use different cadences on the same drive.
    @MainActor
    func testFifteenPercentIsNotLowButFourteenIs() {
        XCTAssertFalse(controller().onBatteryPercent(FakeBatteryProvider(percent: 15).percent!))
        XCTAssertTrue(controller().onBatteryPercent(FakeBatteryProvider(percent: 14).percent!))
        XCTAssertEqual(LOW_BATTERY_PERCENT, 15)
    }

    /// An unknown reading is not a flat battery. `FakeBatteryProvider(percent: nil)` is the
    /// Simulator, and `LocationTracker.checkBattery` must skip it entirely.
    @MainActor
    func testAnUnknownReadingNeverLatchesLowBattery() {
        let provider = FakeBatteryProvider(percent: nil)
        let c = controller()
        XCTAssertNil(provider.percent)
        // Mirrors LocationTracker.checkBattery's `guard let percent = battery.percent`.
        if let percent = provider.percent { _ = c.onBatteryPercent(percent) }
        XCTAssertFalse(c.lowBattery)
        XCTAssertEqual(c.params(), LocationParams(priority: .balanced, minIntervalMs: 30_000, minDisplacementM: 200))
    }
}

// MARK: - D2, near is never downgraded

final class LowBatteryCadenceTests: XCTestCase {

    private func controller() -> TrackingPhaseController {
        TrackingPhaseController(spotLat: 0, spotLng: 0, nearBandM: 3_850, startedAtMs: 0)
    }

    /// Row 3 of the contract's parameters table.
    @MainActor
    func testLowBatteryThinsTheFarPhaseToSixtySecondsAndFourHundredMetres() {
        let c = controller()
        XCTAssertEqual(c.params(), LocationParams(priority: .balanced, minIntervalMs: 30_000, minDisplacementM: 200))
        XCTAssertTrue(c.onBatteryPercent(FakeBatteryProvider(percent: 9).percent!))
        XCTAssertEqual(c.params(), LocationParams(priority: .balanced, minIntervalMs: 60_000, minDisplacementM: 400))
    }

    /// Decision D2, in both orders — battery first then phase, and phase first then battery.
    /// The near row is 5 s / 10 m / high accuracy no matter how the two arrive.
    @MainActor
    func testLowBatteryNeverDowngradesTheNearPhase() {
        let near = LocationParams(priority: .high, minIntervalMs: 5_000, minDisplacementM: 10)
        let provider = FakeBatteryProvider(percent: 9)

        let batteryFirst = controller()
        XCTAssertTrue(batteryFirst.onBatteryPercent(provider.percent!))
        batteryFirst.onServerPhaseHint("near")
        XCTAssertEqual(batteryFirst.params(), near)

        let phaseFirst = controller()
        phaseFirst.onServerPhaseHint("near")
        XCTAssertTrue(phaseFirst.onBatteryPercent(provider.percent!))
        XCTAssertEqual(phaseFirst.params(), near)
        XCTAssertTrue(phaseFirst.lowBattery, "the flag is still set — it just does not apply in near")
    }
}
