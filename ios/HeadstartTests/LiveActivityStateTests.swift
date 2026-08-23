// ios/HeadstartTests/LiveActivityStateTests.swift
//
// The Live Activity's PURE half. A simulator cannot render a Lock Screen Live Activity or
// a Dynamic Island, so the visual is proven by the widget's `#Preview`s and the lifecycle
// by the `[HS][la] started|updated|ended` log lines — never by a faked assertion here.
// What IS testable is the maths, and that is where the actual bugs live: the anchor, the
// lead-time subtraction, the clamp, and the 60-second update threshold.
import XCTest
@testable import Headstart

final class LiveActivityStateTests: XCTestCase {

    private let anchor = Date(timeIntervalSince1970: 1_700_000_000)

    func testWalkOutIsEtaMinusTheLeadTimeMeasuredFromTheServerAnchor() {
        let state = LiveActivityState.make(etaSec: 1_080, leadTimeMin: 3, progressPct: 53, anchor: anchor)
        XCTAssertEqual(state.arriveAt.timeIntervalSince(anchor), 1_080, accuracy: 0.001)
        XCTAssertEqual(state.walkOutAt.timeIntervalSince(anchor), 1_080 - 180, accuracy: 0.001)
        XCTAssertEqual(state.progressPct, 53)
    }

    func testWalkOutNeverPrecedesTheAnchor() {
        let state = LiveActivityState.make(etaSec: 60, leadTimeMin: 3, progressPct: 90, anchor: anchor)
        XCTAssertEqual(state.walkOutAt, anchor)
        XCTAssertEqual(state.arriveAt.timeIntervalSince(anchor), 60, accuracy: 0.001)
    }

    func testProgressIsClamped() {
        XCTAssertEqual(LiveActivityState.make(etaSec: 600, leadTimeMin: 3, progressPct: -5, anchor: anchor).progressPct, 0)
        XCTAssertEqual(LiveActivityState.make(etaSec: 600, leadTimeMin: 3, progressPct: 250, anchor: anchor).progressPct, 100)
    }

    func testANegativeEtaCannotProduceADateBeforeTheAnchor() {
        // The server should never send one, but a reversed range traps Text(timerInterval:).
        let state = LiveActivityState.make(etaSec: -120, leadTimeMin: 3, progressPct: 100, anchor: anchor)
        XCTAssertEqual(state.arriveAt, anchor)
        XCTAssertEqual(state.walkOutAt, anchor)
    }

    func testAnUpdateIsOnlyWorthPushingWhenTheTargetMovesByAMinute() {
        // Mirrors the server's "emit a Live Activity update if ETA changed by >= 60 s".
        let a = LiveActivityState.make(etaSec: 1_080, leadTimeMin: 3, progressPct: 50, anchor: anchor)
        let barelyDifferent = LiveActivityState.make(etaSec: 1_100, leadTimeMin: 3, progressPct: 51, anchor: anchor)
        let reallyDifferent = LiveActivityState.make(etaSec: 1_200, leadTimeMin: 3, progressPct: 55, anchor: anchor)
        XCTAssertFalse(a.isWorthUpdating(to: barelyDifferent))
        XCTAssertTrue(a.isWorthUpdating(to: reallyDifferent))
    }

    func testExactlySixtySecondsIsWorthUpdating() {
        let a = LiveActivityState.make(etaSec: 600, leadTimeMin: 3, progressPct: 0, anchor: anchor)
        let b = LiveActivityState.make(etaSec: 660, leadTimeMin: 3, progressPct: 0, anchor: anchor)
        XCTAssertTrue(a.isWorthUpdating(to: b))
        XCTAssertTrue(b.isWorthUpdating(to: a), "the threshold is symmetric — a trip can speed up")
    }

    func testAWalkOutThatMovesWhileArrivalDoesNotStillCountsAsWorthUpdating() {
        // Same ETA, longer lead time: arriveAt is identical, walkOutAt moves 5 minutes.
        let a = LiveActivityState.make(etaSec: 1_200, leadTimeMin: 3, progressPct: 40, anchor: anchor)
        let b = LiveActivityState.make(etaSec: 1_200, leadTimeMin: 8, progressPct: 40, anchor: anchor)
        XCTAssertEqual(a.arriveAt, b.arriveAt)
        XCTAssertTrue(a.isWorthUpdating(to: b))
    }

    func testBuildsTheStateStraightFromATripDocument() {
        let trip = Trip(id: "t1", data: [
            "pairId": "p1", "driverUid": "d1", "receiverUid": "r1", "spotId": "s1",
            "spot": ["lat": 0, "lng": 0, "radiusM": 100, "name": "Office"],
            "leadTimeMin": 3, "state": "driving", "createdAt": 0,
            "eta": ["seconds": 900, "updatedAt": Int64(anchor.timeIntervalSince1970 * 1000), "approximate": false],
            "receiverView": ["etaSeconds": 900, "progressPct": 40],
        ])!
        let state = LiveActivityState.make(trip: trip)
        XCTAssertEqual(state?.progressPct, 40)
        XCTAssertEqual(state?.walkOutAt.timeIntervalSince(anchor) ?? 0, 900 - 180, accuracy: 1)
    }

    func testTheReceiverProjectionWinsOverTheRawEtaWhenBothArePresent() {
        // ADDENDUM §H — a receiver renders `receiverView` and nothing else. In fuzzy mode
        // the two ETAs legitimately differ, and the Lock Screen must show the receiver's.
        let trip = Trip(id: "t2", data: [
            "pairId": "p1", "driverUid": "d1", "receiverUid": "r1", "spotId": "s1",
            "spot": ["lat": 0, "lng": 0, "radiusM": 100, "name": "Office"],
            "leadTimeMin": 5, "state": "driving", "createdAt": 0,
            "eta": ["seconds": 900, "updatedAt": Int64(anchor.timeIntervalSince1970 * 1000), "approximate": true],
            "receiverView": ["etaSeconds": 600, "progressPct": 70],
        ])!
        let state = LiveActivityState.make(trip: trip)
        XCTAssertEqual(state?.arriveAt.timeIntervalSince(anchor) ?? 0, 600, accuracy: 1)
        XCTAssertEqual(state?.walkOutAt.timeIntervalSince(anchor) ?? 0, 600 - 300, accuracy: 1)
        XCTAssertEqual(state?.approximate, true)
    }

    func testATripWithNoServerEtaHasNothingToCountDownTo() {
        let trip = Trip(id: "t3", data: [
            "pairId": "p1", "driverUid": "d1", "receiverUid": "r1", "spotId": "s1",
            "spot": ["lat": 0, "lng": 0, "radiusM": 100, "name": "Office"],
            "leadTimeMin": 3, "state": "driving", "createdAt": 0,
        ])!
        XCTAssertNil(LiveActivityState.make(trip: trip))
    }

    func testAMissingReceiverViewFallsBackToTheRawEta() {
        let trip = Trip(id: "t4", data: [
            "pairId": "p1", "driverUid": "d1", "receiverUid": "r1", "spotId": "s1",
            "spot": ["lat": 0, "lng": 0, "radiusM": 100, "name": "Office"],
            "leadTimeMin": 3, "state": "driving", "createdAt": 0,
            "eta": ["seconds": 480, "updatedAt": Int64(anchor.timeIntervalSince1970 * 1000)],
        ])!
        let state = LiveActivityState.make(trip: trip)
        XCTAssertEqual(state?.arriveAt.timeIntervalSince(anchor) ?? 0, 480, accuracy: 1)
        XCTAssertEqual(state?.progressPct, 0)
        XCTAssertEqual(state?.approximate, false)
    }
}
