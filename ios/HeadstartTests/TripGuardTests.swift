// ios/HeadstartTests/TripGuardTests.swift
//
// CLIENT_CONTRACT.md §"Shared tracking algorithm":
//
//     Stop tracking immediately when the trip document's state leaves "driving", when the
//     local user taps "I'm here"/"Cancel", or AFTER A 3-HOUR LOCAL GUARD.
//
// The first two are server- and user-driven and are wired in `LocationTracker.applyTrip` /
// `LocationTracker.stop`. The third is purely local arithmetic, and it is the only one of the
// three that can save a person whose phone has lost the trip document — a driver who never
// arrives and never cancels would otherwise upload their position forever. It is therefore
// worth its own file and its own boundary tests.
//
// What is NOT covered here, and cannot be from a unit test: that `LocationTracker.ingest`
// evaluates the guard BEFORE it processes fixes, and calls `stop()` then `onGuardExpired`.
// Reaching that code needs a `CLLocationManager` with granted When-In-Use authorization, which
// a headless XCTest run cannot produce. The ordering is enforced by reading the file — the
// guard is the first statement in `ingest` after the nil checks — and by the drive replay in a
// later batch. Everything the guard DECIDES is here.

import XCTest
@testable import Headstart

private let SPOT_LAT = 23.7806
private let SPOT_LNG = 90.4193
private let T0: Int64 = 1_700_000_000_000
private let THREE_HOURS: Int64 = 3 * 60 * 60 * 1000

private func controller(startedAtMs: Int64 = T0) -> TrackingPhaseController {
    TrackingPhaseController(
        spotLat: SPOT_LAT,
        spotLng: SPOT_LNG,
        nearBandM: 3_850,
        startedAtMs: startedAtMs
    )
}

private func fix(_ lat: Double, _ tsMs: Int64) -> LocationFix {
    LocationFix(lat: lat, lng: SPOT_LNG, accuracyM: 10, speedMps: 12, tsMs: tsMs)
}

final class TripGuardTests: XCTestCase {

    func testTheGuardIsExactlyThreeHours() {
        XCTAssertEqual(TRIP_GUARD_MS, THREE_HOURS)
        XCTAssertEqual(TRIP_GUARD_MS, 10_800_000)
    }

    func testThreeHourLocalGuard() {
        let c = controller(startedAtMs: T0)
        XCTAssertFalse(c.shouldStop(nowMs: T0))
        XCTAssertFalse(c.shouldStop(nowMs: T0 + THREE_HOURS - 1))
        XCTAssertTrue(c.shouldStop(nowMs: T0 + THREE_HOURS))
        XCTAssertTrue(c.shouldStop(nowMs: T0 + 5 * 60 * 60 * 1000))
    }

    /// "after a 3-hour guard" is inclusive at the boundary: at exactly three hours the trip is
    /// over. Both platforms must round the same way, so the millisecond either side is pinned.
    func testTheBoundaryIsInclusive() {
        let c = controller()
        XCTAssertFalse(c.shouldStop(nowMs: T0 + THREE_HOURS - 1), "one ms early is still driving")
        XCTAssertTrue(c.shouldStop(nowMs: T0 + THREE_HOURS), "exactly three hours stops")
        XCTAssertTrue(c.shouldStop(nowMs: T0 + THREE_HOURS + 1))
    }

    /// A trip whose `startedAt` is already three hours in the past — the app was killed
    /// mid-drive and relaunched — must stop on its very first evaluation, before it uploads
    /// anything.
    func testATripResumedAfterTheGuardHasAlreadyExpiredStopsImmediately() {
        let c = controller(startedAtMs: T0 - THREE_HOURS)
        XCTAssertTrue(c.shouldStop(nowMs: T0))
    }

    /// Once expired, always expired. There is no path back to driving.
    func testTheGuardNeverUnfires() {
        let c = controller()
        var everStopped = false
        for hour in 0...6 {
            let now = T0 + Int64(hour) * 60 * 60 * 1000
            let stopped = c.shouldStop(nowMs: now)
            if everStopped { XCTAssertTrue(stopped, "unfired at hour \(hour)") }
            everStopped = everStopped || stopped
        }
        XCTAssertTrue(everStopped)
    }

    /// A clock that jumps backwards (a timezone/NTP correction mid-drive) must not stop the
    /// trip. `nowMs - startedAtMs` goes negative, which is comfortably below the threshold.
    func testAClockThatMovesBackwardsDoesNotStopTheTrip() {
        let c = controller()
        XCTAssertFalse(c.shouldStop(nowMs: T0 - 60_000))
        XCTAssertFalse(c.shouldStop(nowMs: 0))
    }

    /// The guard is wall-clock only. Neither the phase, the battery, nor how many fixes have
    /// been processed may move it — that is what makes it a safety net rather than another
    /// branch of the tracking algorithm.
    func testTheGuardIgnoresPhaseBatteryAndFixHistory() {
        let c = controller()
        _ = c.onFix(fix(SPOT_LAT + 0.1, T0))
        _ = c.onBatteryPercent(9)
        c.onServerPhaseHint("near")
        XCTAssertEqual(c.phase, .near)
        XCTAssertTrue(c.lowBattery)

        XCTAssertFalse(c.shouldStop(nowMs: T0 + THREE_HOURS - 1))
        XCTAssertTrue(c.shouldStop(nowMs: T0 + THREE_HOURS))
    }

    /// A three-hour drive at 1 Hz: the controller keeps accepting fixes right up to the
    /// boundary and the guard is what ends it, not the fixes themselves.
    func testAThreeHourDriveIsStoppedByTheGuardAndNotByTheUploadFilter() {
        let c = controller()
        var lastAcceptedTs: Int64 = 0
        var stoppedAt: Int64?
        var ts = T0
        // Sample every 10 minutes rather than every second: this asserts the guard, and the
        // upload filter has its own exhaustive tests.
        while ts <= T0 + THREE_HOURS + 600_000 {
            if c.shouldStop(nowMs: ts) {
                stoppedAt = ts
                break
            }
            // Still far from the spot, moving ~1 km every ten minutes.
            let lat = SPOT_LAT + 0.5 - Double(ts - T0) / Double(THREE_HOURS) * 0.4
            if case .upload(let accepted, _) = c.onFix(fix(lat, ts)) {
                lastAcceptedTs = accepted.tsMs
            }
            ts += 600_000
        }
        XCTAssertEqual(stoppedAt, T0 + THREE_HOURS)
        XCTAssertEqual(lastAcceptedTs, T0 + THREE_HOURS - 600_000,
                       "fixes were still being accepted right up to the guard")
    }
}
