// ios/HeadstartTests/ModelsTests.swift
//
// The mappers are pure functions over `[String: Any]`, so they are table-tested against
// realistic Firestore payloads — including documents with fields missing, fields the server
// has not written yet, and fields of the wrong type. The rule every mapper obeys: return
// nil (or a sensible default) rather than trap.

import XCTest
@testable import Headstart

private let T0: Int64 = 1_700_000_000_000

private func fullTripData() -> [String: Any] {
    [
        "pairId": "p1",
        "driverUid": "d1",
        "receiverUid": "r1",
        "spotId": "s1",
        "spot": ["lat": 23.75, "lng": 90.39, "radiusM": 100, "name": "Office"],
        "leadTimeMin": 3,
        "state": "driving",
        "createdAt": T0,
        "startedAt": T0,
        "eta": ["seconds": 1_080, "updatedAt": T0, "approximate": false],
        "bands": ["far": 6_600, "near": 3_850, "lead": 2_750],
        "phaseHint": "far",
        "routePolyline": "_p~iF~ps|U",
        "receiverView": ["etaSeconds": 1_080, "progressPct": 53, "lastPos": ["lat": 23.8, "lng": 90.4]],
        "alerts": [
            "started": true, "tenMin": false, "leadTime": false,
            "arrived": false, "didYouLeave": false, "slipCount": 0,
        ],
        "fuzzy": false,
    ]
}

final class TripMappingTests: XCTestCase {

    func testMapsAFullyPopulatedTrip() {
        let trip = Trip(id: "t1", data: fullTripData())
        XCTAssertNotNil(trip)
        guard let trip else { return }
        XCTAssertEqual(trip.id, "t1")
        XCTAssertEqual(trip.pairId, "p1")
        XCTAssertEqual(trip.driverUid, "d1")
        XCTAssertEqual(trip.receiverUid, "r1")
        XCTAssertEqual(trip.spotId, "s1")
        XCTAssertEqual(trip.state, .driving)
        XCTAssertEqual(trip.leadTimeMin, 3)
        XCTAssertEqual(trip.spot.name, "Office")
        XCTAssertEqual(trip.spot.radiusM, 100)
        XCTAssertEqual(trip.eta?.seconds, 1_080)
        XCTAssertEqual(trip.eta?.approximate, false)
        XCTAssertEqual(trip.bands?.far, 6_600)
        XCTAssertEqual(trip.bands?.near, 3_850)
        XCTAssertEqual(trip.bands?.lead, 2_750)
        XCTAssertEqual(trip.phaseHint, "far")
        XCTAssertEqual(trip.routePolyline, "_p~iF~ps|U")
        XCTAssertEqual(trip.receiverView?.progressPct, 53)
        XCTAssertEqual(trip.receiverView?.point?.lat, 23.8)
        XCTAssertTrue(trip.alerts.started)
        XCTAssertEqual(trip.alerts.slipCount, 0)
        XCTAssertFalse(trip.fuzzy)
    }

    func testAPartlyWrittenTripStillMaps() {
        // armTrip writes no eta, no bands, no receiverView, no startedAt.
        var data = fullTripData()
        for key in ["eta", "bands", "receiverView", "startedAt", "routePolyline"] {
            data.removeValue(forKey: key)
        }
        data["state"] = "armed"
        let trip = Trip(id: "t1", data: data)
        XCTAssertNotNil(trip)
        XCTAssertEqual(trip?.state, .armed)
        XCTAssertNil(trip?.eta)
        XCTAssertNil(trip?.bands)
        XCTAssertNil(trip?.receiverView)
        XCTAssertNil(trip?.startedAt)
        XCTAssertNil(trip?.routePolyline)
        XCTAssertEqual(trip?.isLive, true)
    }

    /// ADDENDUM §I — every alert flag is absent until it first fires; a mapper must never
    /// trap on one, and a whole missing `alerts` map is the normal case at trip creation.
    func testMissingAlertsDefaultToAllFalse() {
        var data = fullTripData()
        data.removeValue(forKey: "alerts")
        XCTAssertEqual(Trip(id: "t1", data: data)?.alerts, TripAlerts())
    }

    func testAPartialAlertsMapKeepsWhatIsThereAndDefaultsTheRest() {
        var data = fullTripData()
        data["alerts"] = ["started": true, "tenMin": true, "slipCount": 2]
        let alerts = Trip(id: "t1", data: data)?.alerts
        XCTAssertEqual(alerts?.started, true)
        XCTAssertEqual(alerts?.tenMin, true)
        XCTAssertEqual(alerts?.leadTime, false)
        XCTAssertEqual(alerts?.arrived, false)
        XCTAssertEqual(alerts?.didYouLeave, false)
        XCTAssertEqual(alerts?.slipCount, 2)
    }

    /// The spec's seventh alert field is server-internal (ADDENDUM §I). Its presence must
    /// not disturb anything; it simply is not modelled.
    func testTheSpecsServerInternalAlertFieldIsIgnored() {
        var data = fullTripData()
        var alerts = data["alerts"] as! [String: Any]
        alerts["lastSlipEtaSec"] = 940
        data["alerts"] = alerts
        let trip = Trip(id: "t1", data: data)
        XCTAssertNotNil(trip)
        XCTAssertEqual(trip?.alerts.slipCount, 0)
    }

    func testADocumentMissingARequiredFieldIsRejected() {
        for missing in ["driverUid", "receiverUid", "spot", "state", "pairId"] {
            var data = fullTripData()
            data.removeValue(forKey: missing)
            XCTAssertNil(Trip(id: "t1", data: data), "should reject a trip with no \(missing)")
        }
    }

    func testAWronglyTypedRequiredFieldIsRejectedRatherThanCrashing() {
        let wrong: [(String, Any)] = [
            ("pairId", 42),
            ("driverUid", ["nested": true]),
            ("receiverUid", NSNull()),
            ("state", 7),
            ("spot", "Office"),                                   // string where a map belongs
            ("spot", ["lat": "north", "lng": 90.39, "name": "X"]), // unparseable lat
            ("spot", ["lat": 23.75, "lng": 90.39]),                // no name
        ]
        for (key, value) in wrong {
            var data = fullTripData()
            data[key] = value
            XCTAssertNil(Trip(id: "t1", data: data), "should reject \(key) = \(value)")
        }
    }

    func testAWronglyTypedOptionalFieldFallsBackInsteadOfRejecting() {
        var data = fullTripData()
        data["leadTimeMin"] = "three"
        data["phaseHint"] = 9
        data["routePolyline"] = 12
        data["fuzzy"] = "yes"
        data["eta"] = "soon"
        data["bands"] = ["far": 6_600, "near": 3_850]   // short: no lead
        data["receiverView"] = ["progressPct": 53]      // short: no etaSeconds
        let trip = Trip(id: "t1", data: data)
        XCTAssertNotNil(trip)
        XCTAssertEqual(trip?.leadTimeMin, 3)            // SpotLimits.defaultLeadTimeMin
        XCTAssertEqual(trip?.phaseHint, "far")
        XCTAssertNil(trip?.routePolyline)
        XCTAssertEqual(trip?.fuzzy, false)
        XCTAssertNil(trip?.eta)
        XCTAssertNil(trip?.bands)
        XCTAssertNil(trip?.receiverView)
    }

    func testNumbersSurviveWhicheverBoxFirestoreUses() {
        var data = fullTripData()
        data["leadTimeMin"] = NSNumber(value: 3.0)          // came back as a Double
        data["createdAt"] = NSNumber(value: Double(T0))     // came back as a Double
        data["spot"] = ["lat": 23.75, "lng": 90.39, "radiusM": NSNumber(value: 100), "name": "Office"]
        let trip = Trip(id: "t1", data: data)
        XCTAssertEqual(trip?.leadTimeMin, 3)
        XCTAssertEqual(trip?.createdAt, T0)
        XCTAssertEqual(trip?.spot.radiusM, 100)
    }

    /// A boolean is boxed as an NSNumber too. Reading `alerts.started` through the numeric
    /// reader would silently turn a flag into a count, so the readers keep them apart.
    func testABooleanIsNotReadAsANumber() {
        var data = fullTripData()
        data["alerts"] = ["slipCount": true]
        XCTAssertEqual(Trip(id: "t1", data: data)?.alerts.slipCount, 0)
    }

    func testUnknownStateFallsBackToLostRatherThanDroppingTheTrip() {
        var data = fullTripData()
        data["state"] = "something-new"
        let trip = Trip(id: "t1", data: data)
        XCTAssertEqual(trip?.state, .lost)
        XCTAssertEqual(trip?.isLive, false)
    }

    func testEveryContractTripStateRoundTrips() {
        for state in TripState.allCases {
            var data = fullTripData()
            data["state"] = state.rawValue
            XCTAssertEqual(Trip(id: "t1", data: data)?.state, state, state.rawValue)
        }
    }

    func testRoleHelpers() {
        let trip = Trip(id: "t1", data: fullTripData())!
        XCTAssertEqual(trip.role(for: "d1"), .driver)
        XCTAssertEqual(trip.role(for: "r1"), .receiver)
        XCTAssertNil(trip.role(for: "someone-else"))
        XCTAssertEqual(trip.otherUid(for: "d1"), "r1")
        XCTAssertEqual(trip.otherUid(for: "r1"), "d1")
        XCTAssertNil(trip.otherUid(for: "someone-else"))
        XCTAssertTrue(trip.isLive)
    }

    func testWalkOutSecondsIsEtaMinusTheLeadTime() {
        let trip = Trip(id: "t1", data: fullTripData())!    // eta 1080, lead 3 min
        XCTAssertEqual(trip.walkOutSeconds, 1_080 - 180)
        var late = fullTripData()
        late["eta"] = ["seconds": 60, "updatedAt": T0, "approximate": false]
        XCTAssertEqual(Trip(id: "t1", data: late)!.walkOutSeconds, 0)   // never negative
        var noEta = fullTripData()
        noEta.removeValue(forKey: "eta")
        XCTAssertEqual(Trip(id: "t1", data: noEta)!.walkOutSeconds, 0)
    }

    /// CLIENT_CONTRACT.md line 39 / ADDENDUM §H, enforced structurally: the receiver's only
    /// position source is the server's `receiverView` projection, and `Trip` has no
    /// top-level position property at all — the field cannot be reached from Swift even
    /// though it is present in the snapshot.
    func testTheDriversRawPositionIsNotReachableFromTheTripModel() {
        var data = fullTripData()
        data["lastPos"] = ["lat": 23.9, "lng": 90.5, "ts": T0]
        let trip = Trip(id: "t1", data: data)!
        XCTAssertEqual(trip.receiverView?.point, LatLng(lat: 23.8, lng: 90.4))
        let mirrored = Mirror(reflecting: trip).children.compactMap(\.label)
        XCTAssertFalse(mirrored.contains("lastPos"), "Trip must not expose the raw driver position")
    }

    /// Fuzzy mode is the server omitting the point from the projection. The client renders
    /// what it is given and decides nothing.
    func testFuzzyModeArrivesAsAProjectionWithNoPoint() {
        var data = fullTripData()
        data["fuzzy"] = true
        data["receiverView"] = ["etaSeconds": 1_080, "progressPct": 53]
        let trip = Trip(id: "t1", data: data)
        XCTAssertEqual(trip?.fuzzy, true)
        XCTAssertEqual(trip?.receiverView?.etaSeconds, 1_080)
        XCTAssertNil(trip?.receiverView?.point)
    }
}

final class PairAndSpotMappingTests: XCTestCase {

    func testMapsAPair() {
        let pair = Pair(id: "p1", data: [
            "members": ["a", "b"], "status": "active",
            "memberNames": ["a": "Mostafi", "b": "Sara"],
            "inviteCode": "K7M2QP", "createdBy": "a", "createdAt": T0,
        ])
        XCTAssertEqual(pair?.members, ["a", "b"])
        XCTAssertTrue(pair!.isActive)
        XCTAssertFalse(pair!.isPending)
        XCTAssertEqual(pair?.inviteCode, "K7M2QP")
        XCTAssertEqual(pair?.createdAt, T0)
        XCTAssertEqual(pair?.other(than: "a"), "b")
        XCTAssertEqual(pair?.other(than: "b"), "a")
        XCTAssertEqual(pair?.memberNames["b"], "Sara")
    }

    func testAPendingPairHasNoOtherMemberYet() {
        let pair = Pair(id: "p1", data: [
            "members": ["a"], "status": "pending",
            "inviteCode": "K7M2QP", "createdBy": "a", "createdAt": T0,
        ])
        XCTAssertFalse(pair!.isActive)
        XCTAssertTrue(pair!.isPending)
        XCTAssertNil(pair?.other(than: "a"))
        XCTAssertEqual(pair?.memberNames, [:])
    }

    func testAPairMissingARequiredFieldIsRejected() {
        for missing in ["members", "status", "inviteCode", "createdBy"] {
            var data: [String: Any] = [
                "members": ["a", "b"], "status": "active",
                "inviteCode": "K7M2QP", "createdBy": "a", "createdAt": T0,
            ]
            data.removeValue(forKey: missing)
            XCTAssertNil(Pair(id: "p1", data: data), "should reject a pair with no \(missing)")
        }
    }

    func testANonStringEntryInMemberNamesIsDroppedNotFatal() {
        let pair = Pair(id: "p1", data: [
            "members": ["a", "b"], "status": "active",
            "memberNames": ["a": "Mostafi", "b": 7],
            "inviteCode": "K7M2QP", "createdBy": "a", "createdAt": T0,
        ])
        XCTAssertEqual(pair?.memberNames, ["a": "Mostafi"])
    }

    func testMapsASpotAndClampsNothingOnRead() {
        // Clamping happens on the WRITE path (Callables/SpotLimits, ADDENDUM §K); a read
        // shows what is stored, whatever the server put there.
        let spot = Spot(id: "s1", data: [
            "pairId": "p1", "name": "Office", "lat": 23.75, "lng": 90.39,
            "radiusM": 100, "leadTimeMin": 3, "createdBy": "r1", "createdAt": T0,
        ])
        XCTAssertEqual(spot?.name, "Office")
        XCTAssertEqual(spot?.leadTimeMin, 3)
        XCTAssertEqual(spot?.radiusM, 100)
        XCTAssertEqual(spot?.coordinate, LatLng(lat: 23.75, lng: 90.39))
    }

    func testASpotWithoutCoordinatesIsRejected() {
        XCTAssertNil(Spot(id: "s1", data: ["pairId": "p1", "name": "Office"]))
        XCTAssertNil(Spot(id: "s1", data: ["pairId": "p1", "lat": 23.75, "lng": 90.39]))
        XCTAssertNil(Spot(id: "s1", data: ["name": "Office", "lat": 23.75, "lng": 90.39]))
    }

    func testASpotFallsBackToTheContractDefaults() {
        let spot = Spot(id: "s1", data: [
            "pairId": "p1", "name": "Office", "lat": 23.75, "lng": 90.39,
        ])
        XCTAssertEqual(spot?.radiusM, 100)      // spec default
        XCTAssertEqual(spot?.leadTimeMin, 3)    // spec default
        XCTAssertEqual(spot?.createdBy, "")
        XCTAssertEqual(spot?.createdAt, 0)
    }

    func testMapsAReply() {
        let reply = Reply(id: "x", data: [
            "fromUid": "r1", "kind": "takeYourTime", "text": "Take your time", "ts": T0,
        ])
        XCTAssertEqual(reply?.text, "Take your time")
        XCTAssertEqual(reply?.kind, "takeYourTime")
        XCTAssertEqual(reply?.ts, T0)
    }

    /// A reply the server invented must render, not crash — the write side is the closed
    /// `ReplyKind` enum, the read side is a plain string (ADDENDUM §B).
    func testAReplyOfAnUnknownKindStillMaps() {
        let reply = Reply(id: "x", data: ["fromUid": "r1", "kind": "somethingNew", "ts": T0])
        XCTAssertEqual(reply?.kind, "somethingNew")
        XCTAssertEqual(reply?.text, "")
    }

    func testAReplyWithoutASenderIsRejected() {
        XCTAssertNil(Reply(id: "x", data: ["kind": "atSpot", "ts": T0]))
    }
}

final class SpotLimitsTests: XCTestCase {

    /// ADDENDUM §K — the client clamps to exactly the server's ranges so a person never
    /// sees a raw callable error.
    func testClampsMatchTheContractRanges() {
        XCTAssertEqual(SpotLimits.clampLeadTimeMin(0), 1)
        XCTAssertEqual(SpotLimits.clampLeadTimeMin(3), 3)
        XCTAssertEqual(SpotLimits.clampLeadTimeMin(99), 30)
        XCTAssertEqual(SpotLimits.clampRadiusM(10), 50)
        XCTAssertEqual(SpotLimits.clampRadiusM(100), 100)
        XCTAssertEqual(SpotLimits.clampRadiusM(9_000), 500)
        XCTAssertEqual(SpotLimits.clampExtraMin(0), 1)
        XCTAssertEqual(SpotLimits.clampExtraMin(15), 15)
        XCTAssertEqual(SpotLimits.clampExtraMin(600), 60)
    }
}

/// The write side of the contract. `documentFields(for:)` is the same dictionary
/// `FirestorePositionSink.write` hands to `addDocument`, so this assertion cannot drift
/// away from the actual write. It needs no Firestore instance and no network.
final class PositionDocumentShapeTests: XCTestCase {

    private let fix = PositionUpload(
        lat: 23.75, lng: 90.39, accuracyM: 12, speedMps: 8.5, ts: T0, etaSec: 940
    )

    /// ADDENDUM §J — exactly six keys, plus `etaSec` when present. Rules reject extras.
    func testTheDocumentHasExactlyTheContractKeys() {
        let withEta = FirestorePositionSink.documentFields(for: fix)
        XCTAssertEqual(
            Set(withEta.keys),
            ["lat", "lng", "accuracyM", "speedMps", "ts", "expireAt", "etaSec"]
        )
        XCTAssertEqual(withEta["lat"] as? Double, 23.75)
        XCTAssertEqual(withEta["lng"] as? Double, 90.39)
        XCTAssertEqual(withEta["accuracyM"] as? Double, 12)
        XCTAssertEqual(withEta["speedMps"] as? Double, 8.5)
        XCTAssertEqual((withEta["ts"] as? NSNumber)?.int64Value, T0)
        XCTAssertEqual((withEta["etaSec"] as? NSNumber)?.intValue, 940)
    }

    /// A missing ETA is an ABSENT key, never NSNull — NSNull would be a seventh/eighth key
    /// and the rules would reject the write.
    func testAMissingEtaOmitsTheKeyEntirely() {
        var noEta = fix
        noEta.etaSec = nil
        let data = FirestorePositionSink.documentFields(for: noEta)
        XCTAssertEqual(Set(data.keys), Set(FirestorePositionSink.requiredKeys))
        XCTAssertNil(data["etaSec"])
        XCTAssertFalse(data.values.contains { $0 is NSNull })
    }

    /// `expireAt` is a real 30-day-out timestamp, not a serverTimestamp sentinel: a
    /// sentinel arrives as a pending value the TTL policy cannot use.
    func testExpireAtIsAConcreteThirtyDayTimestamp() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let data = FirestorePositionSink.documentFields(for: fix, now: now)
        // Read through KVC rather than naming `Timestamp`, so the test target needs no
        // direct Firebase import. `FIRTimestamp.seconds` is an ObjC readonly property.
        let expireAt = data["expireAt"] as AnyObject
        XCTAssertEqual(NSStringFromClass(type(of: expireAt)), "FIRTimestamp")
        XCTAssertEqual(
            expireAt.value(forKey: "seconds") as? Int64,
            Int64(now.timeIntervalSince1970 + FirestorePositionSink.ttl)
        )
    }

    /// PositionUpload already clamps CoreLocation's -1 "speed unknown" to 0 (ios2); this
    /// asserts the sink does not undo it.
    func testAnUnknownSpeedReachesTheWireAsZero() {
        let unknown = PositionUpload(
            fix: LocationFix(lat: 23.75, lng: 90.39, accuracyM: 12, speedMps: -1, tsMs: T0),
            etaSec: nil
        )
        let data = FirestorePositionSink.documentFields(for: unknown)
        XCTAssertEqual(data["speedMps"] as? Double, 0)
    }
}
