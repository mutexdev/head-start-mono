// ios/HeadstartTests/TrackingPhaseControllerTests.swift
import XCTest
@testable import Headstart

/// The spot sits at (0,0). One degree of latitude is ~111.19 km, so lat 0.001 is ~111 m
/// and lat 0.01 is ~1111 m — handy round numbers for the tables below.
private let SPOT_LAT = 0.0
private let SPOT_LNG = 0.0
private let T0: Int64 = 1_700_000_000_000
private let NEAR_BAND = 3_850.0

private func controller(
    nearBandM: Double = NEAR_BAND,
    startedAtMs: Int64 = T0
) -> TrackingPhaseController {
    TrackingPhaseController(
        spotLat: SPOT_LAT,
        spotLng: SPOT_LNG,
        nearBandM: nearBandM,
        startedAtMs: startedAtMs
    )
}

private func fix(
    _ lat: Double,
    _ tsMs: Int64,
    accuracyM: Double = 10,
    speedMps: Double = 12,
    lng: Double = 0
) -> LocationFix {
    LocationFix(lat: lat, lng: lng, accuracyM: accuracyM, speedMps: speedMps, tsMs: tsMs)
}

private func isUpload(_ d: FixDecision) -> Bool {
    if case .upload = d { return true }
    return false
}

private func skipReason(_ d: FixDecision) -> SkipReason? {
    if case .skip(let r) = d { return r }
    return nil
}

private func uploadPhase(_ d: FixDecision) -> Phase? {
    if case .upload(_, let phase) = d { return phase }
    return nil
}

final class HaversineTests: XCTestCase {

    func testIdenticalPointsAreZeroMetresApart() {
        XCTAssertEqual(haversineMeters(1, 1, 1, 1), 0, accuracy: 0.001)
    }

    func testOneDegreeOfLatitudeIsAboutOneHundredAndElevenKilometres() {
        let d = haversineMeters(0, 0, 1, 0)
        XCTAssertGreaterThan(d, 110_000)
        XCTAssertLessThan(d, 112_000)
    }

    func testIsSymmetric() {
        let a = haversineMeters(23.78, 90.41, 23.75, 90.39)
        let b = haversineMeters(23.75, 90.39, 23.78, 90.41)
        XCTAssertEqual(a, b, accuracy: 0.0001)
    }
}

final class PhaseTransitionTests: XCTestCase {

    func testStartsInFar() {
        XCTAssertEqual(controller().phase, .far)
    }

    func testServerPhaseHintNearLatchesThePhase() {
        let c = controller()
        c.onServerPhaseHint("near")
        XCTAssertEqual(c.phase, .near)
    }

    func testServerPhaseHintFarDoesNotMoveThePhaseBack() {
        let c = controller()
        c.onServerPhaseHint("near")
        c.onServerPhaseHint("far")
        XCTAssertEqual(c.phase, .near)
    }

    func testUnknownOrNilPhaseHintIsIgnored() {
        let c = controller()
        c.onServerPhaseHint(nil)
        c.onServerPhaseHint("")
        c.onServerPhaseHint("NEAR")   // case-sensitive on purpose: the server sends "near"
        XCTAssertEqual(c.phase, .far)
    }

    func testDistanceTableDrivesThePhase() {
        // lat -> expected phase after that single fix, with nearBand = 3850 m
        let table: [(Double, Phase)] = [
            (0.100, .far),    // ~11.1 km out
            (0.050, .far),    // ~5.6 km out
            (0.0347, .far),   // ~3.86 km out, just outside the band
            (0.0346, .near),  // ~3.85 km out, on the band
            (0.0100, .near),  // ~1.1 km out
            (0.0001, .near),  // ~11 m out
        ]
        for (lat, expected) in table {
            let c = controller()
            _ = c.onFix(fix(lat, T0))
            XCTAssertEqual(c.phase, expected, "lat \(lat)")
        }
    }

    func testPhaseNeverReturnsToFarOnceNear() {
        let c = controller()
        _ = c.onFix(fix(0.010, T0))                 // inside the band -> near
        XCTAssertEqual(c.phase, .near)
        _ = c.onFix(fix(0.100, T0 + 60_000))        // driver overshoots and drives away
        XCTAssertEqual(c.phase, .near)
    }

    func testALowAccuracyFixCannotLatchThePhase() {
        // Decision D1.
        let c = controller()
        let decision = c.onFix(fix(0.001, T0, accuracyM: 900))
        XCTAssertEqual(skipReason(decision), .lowAccuracy)
        XCTAssertEqual(c.phase, .far)
    }

    func testALowAccuracyFixNeverBecomesTheUploadBaseline() {
        // Decision D1, the other half: a junk fix must not poison `lastUploaded` either.
        let c = controller()
        XCTAssertEqual(skipReason(c.onFix(fix(0.100, T0, accuracyM: 900))), .lowAccuracy)
        XCTAssertNil(c.lastUploaded)
        XCTAssertTrue(isUpload(c.onFix(fix(0.100, T0 + 1_000))))
    }
}

final class LocationParamsTests: XCTestCase {

    func testParameterTableMatchesTheContract() {
        let far = controller()
        XCTAssertEqual(far.params(), LocationParams(priority: .balanced, minIntervalMs: 30_000, minDisplacementM: 200))

        let farLow = controller()
        _ = farLow.onBatteryPercent(9)
        XCTAssertEqual(farLow.params(), LocationParams(priority: .balanced, minIntervalMs: 60_000, minDisplacementM: 400))

        let near = controller()
        near.onServerPhaseHint("near")
        XCTAssertEqual(near.params(), LocationParams(priority: .high, minIntervalMs: 5_000, minDisplacementM: 10))

        // Decision D2: low battery never downgrades the near phase.
        let nearLow = controller()
        nearLow.onServerPhaseHint("near")
        _ = nearLow.onBatteryPercent(3)
        XCTAssertEqual(nearLow.params(), LocationParams(priority: .high, minIntervalMs: 5_000, minDisplacementM: 10))
    }

    func testBatteryReportsAtOrAboveFifteenPercentDoNotTripLowBattery() {
        let c = controller()
        XCTAssertFalse(c.onBatteryPercent(15))
        XCTAssertFalse(c.onBatteryPercent(100))
        XCTAssertFalse(c.lowBattery)
    }

    func testLowBatteryIsReportedExactlyOnceAndThenLatches() {
        // Decision D3.
        let c = controller()
        XCTAssertTrue(c.onBatteryPercent(14))
        XCTAssertFalse(c.onBatteryPercent(9))
        XCTAssertFalse(c.onBatteryPercent(80))   // charger plugged in mid-trip
        XCTAssertTrue(c.lowBattery)
    }

    func testANonsenseBatteryPercentIsIgnored() {
        // UIDevice reports -1 when battery monitoring has not started yet.
        let c = controller()
        XCTAssertFalse(c.onBatteryPercent(-1))
        XCTAssertFalse(c.lowBattery)
    }
}

final class UploadFilterTests: XCTestCase {

    func testTheFirstAcceptableFixIsAlwaysUploaded() {
        let c = controller()
        let d = c.onFix(fix(0.100, T0))
        XCTAssertTrue(isUpload(d))
        XCTAssertEqual(uploadPhase(d), .far)
    }

    func testConditionOneFixesWorseThanOneHundredMetresAccuracyAreDropped() {
        let c = controller()
        _ = c.onFix(fix(0.100, T0))
        let table: [(Double, Bool)] = [
            (100.0, true),    // exactly 100 m is acceptable
            (100.1, false),
            (250.0, false),
        ]
        for (accuracy, acceptable) in table {
            let d = c.onFix(fix(0.050, T0 + 600_000, accuracyM: accuracy))
            if acceptable {
                XCTAssertTrue(isUpload(d), "accuracy \(accuracy)")
            } else {
                XCTAssertEqual(skipReason(d), .lowAccuracy, "accuracy \(accuracy)")
            }
        }
    }

    func testConditionTwoATimestampNotStrictlyGreaterThanTheLastUploadIsDropped() {
        let c = controller()
        _ = c.onFix(fix(0.100, T0 + 60_000))
        XCTAssertEqual(skipReason(c.onFix(fix(0.050, T0 + 60_000))), .staleTimestamp)
        XCTAssertEqual(skipReason(c.onFix(fix(0.050, T0 + 30_000))), .staleTimestamp)
    }

    func testConditionThreeInFarPhaseThirtySecondsOrTwoHundredMetres() {
        // (elapsed ms since last upload, metres moved, expected upload?)
        let table: [(Int64, Double, Bool)] = [
            (1_000, 10, false),
            (1_000, 199, false),
            (1_000, 201, true),    // displacement wins
            (29_999, 5, false),
            (30_000, 5, true),     // interval wins
            (120_000, 0, true),
        ]
        for (elapsed, metres, expected) in table {
            let c = controller()
            _ = c.onFix(fix(0.100, T0))
            // 0.100 lat is the anchor; move north by `metres` (1 deg lat ~ 111_190 m).
            let lat = 0.100 + metres / 111_190.0
            let d = c.onFix(fix(lat, T0 + elapsed))
            XCTAssertEqual(isUpload(d), expected, "elapsed \(elapsed) moved \(metres)")
        }
    }

    func testConditionThreeInNearPhaseFiveSecondsOrTenMetres() {
        let table: [(Int64, Double, Bool)] = [
            (1_000, 2, false),
            (1_000, 11, true),
            (4_999, 1, false),
            (5_000, 1, true),
        ]
        for (elapsed, metres, expected) in table {
            let c = controller()
            c.onServerPhaseHint("near")
            _ = c.onFix(fix(0.0100, T0))
            let lat = 0.0100 + metres / 111_190.0
            let d = c.onFix(fix(lat, T0 + elapsed))
            XCTAssertEqual(isUpload(d), expected, "elapsed \(elapsed) moved \(metres)")
        }
    }

    func testConditionThreeInFarPhaseOnLowBatterySixtySecondsOrFourHundredMetres() {
        let table: [(Int64, Double, Bool)] = [
            (30_000, 5, false),
            (59_999, 5, false),
            (60_000, 5, true),
            (1_000, 399, false),
            (1_000, 401, true),
        ]
        for (elapsed, metres, expected) in table {
            let c = controller()
            _ = c.onBatteryPercent(11)
            _ = c.onFix(fix(0.100, T0))
            let lat = 0.100 + metres / 111_190.0
            let d = c.onFix(fix(lat, T0 + elapsed))
            XCTAssertEqual(isUpload(d), expected, "elapsed \(elapsed) moved \(metres)")
        }
    }

    func testASkippedFixDoesNotBecomeTheNewBaseline() {
        let c = controller()
        _ = c.onFix(fix(0.100, T0))
        _ = c.onFix(fix(0.1001, T0 + 1_000))   // ~11 m, skipped in far phase
        XCTAssertEqual(c.lastUploaded?.tsMs, T0)
        // 30 s after the *uploaded* fix, not after the skipped one:
        let d = c.onFix(fix(0.1001, T0 + 30_000))
        XCTAssertTrue(isUpload(d))
        XCTAssertEqual(c.lastUploaded?.tsMs, T0 + 30_000)
    }

    func testCrossingIntoTheNearBandAppliesNearRulesToThatSameFix() {
        // Decision D4.
        let c = controller()
        _ = c.onFix(fix(0.100, T0))                    // far baseline
        let d = c.onFix(fix(0.0100, T0 + 6_000))       // enters the band, 6 s later
        XCTAssertEqual(c.phase, .near)
        XCTAssertTrue(isUpload(d))
        XCTAssertEqual(uploadPhase(d), .near)
    }
}

// `TripGuardTests` used to live here. It now has its own file, HeadstartTests/TripGuardTests.swift,
// where it is expanded to cover the boundary, monotonicity and clock skew. Two classes with the
// same name in one test target do not compile, so it is gone from here on purpose.

final class RealisticDriveTests: XCTestCase {

    /// 11 km straight-line approach at ~12 m/s with a 1 Hz location stream, low accuracy
    /// noise every 20th fix. Asserts the shape of the whole trip rather than one branch.
    func testASimulatedDriveUploadsASaneNumberOfFixesAndEndsInNear() {
        let c = controller()
        var uploads = 0
        var nearUploads = 0
        let totalMetres = 11_000.0
        let steps = 900                                  // 900 s of driving
        for i in 0..<steps {
            let remaining = totalMetres * (1.0 - Double(i) / Double(steps))
            let lat = remaining / 111_190.0
            let accuracy: Double = i % 20 == 0 ? 400 : 12
            let d = c.onFix(fix(lat, T0 + Int64(i) * 1_000, accuracyM: accuracy))
            if case .upload(_, let phase) = d {
                uploads += 1
                if phase == .near { nearUploads += 1 }
            }
        }
        XCTAssertEqual(c.phase, .near)
        // The plan doc's prose guessed "near: ~300 s at 5 s -> ~60" and bounded the total at
        // 160. That is wrong under CLIENT_CONTRACT.md's upload filter, which is an OR: at
        // 12 m/s a 1 Hz stream moves ~12.2 m per fix, which already clears the near phase's
        // 10 m displacement rule, so near uploads every fix rather than every fifth. The
        // contract's table wins over the plan's arithmetic. Measured here: 334 uploads, 299
        // of them near. Bounds widened to bracket that with room for float drift.
        XCTAssertGreaterThan(uploads, 40)
        XCTAssertLessThan(uploads, 400)
        XCTAssertGreaterThan(nearUploads, 20)
        // far phase: ~585 s at one upload per 200 m (~16 s) -> ~35
        XCTAssertGreaterThan(uploads - nearUploads, 20)
        XCTAssertLessThan(uploads - nearUploads, 60)
    }

    /// The same drive with the low-battery row latched before the first fix: far-phase
    /// uploads must thin out (60 s / 400 m), and the near phase must be untouched (D2).
    func testTheLowBatteryRowThinsTheFarPhaseButNotTheNearPhase() {
        let normal = controller()
        let low = controller()
        _ = low.onBatteryPercent(9)
        var normalFar = 0
        var lowFar = 0
        var lowNear = 0
        for i in 0..<900 {
            let lat = 11_000.0 * (1.0 - Double(i) / 900.0) / 111_190.0
            let f = fix(lat, T0 + Int64(i) * 1_000)
            if case .upload(_, let phase) = normal.onFix(f), phase == .far { normalFar += 1 }
            if case .upload(_, let phase) = low.onFix(f) {
                if phase == .far { lowFar += 1 } else { lowNear += 1 }
            }
        }
        XCTAssertLessThan(lowFar, normalFar)
        XCTAssertEqual(low.params(), LocationParams(priority: .high, minIntervalMs: 5_000, minDisplacementM: 10))
        XCTAssertGreaterThan(lowNear, 20)
    }
}
