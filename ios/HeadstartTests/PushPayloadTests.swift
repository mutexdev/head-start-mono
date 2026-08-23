// ios/HeadstartTests/PushPayloadTests.swift
//
// This is where the real push coverage lives. Nothing on this machine can deliver a real
// FCM message — no APNs key, no paid team, no phone — so the parser and the routing rules
// are the part that gets asserted, and delivery itself is proven separately by
// `xcrun simctl push ios/fixtures/push/<kind>.apns` plus the `[HS][push] kind=…` log line.
//
// Two userInfo shapes are table-tested for every one of the thirteen contract kinds:
//   FLATTENED — what real FCM produces (the `data` map lands on the APNs root)
//   NESTED    — what the committed `.apns` fixtures and the `_debugPushes` rows carry
// If either shape ever stops parsing, half the delivery paths go silently dead.
import XCTest
@testable import Headstart

final class PushPayloadTests: XCTestCase {

    // MARK: - Builders

    /// Real FCM: `data` keys flattened onto the APNs root.
    private func flattened(
        kind: String?,
        tripId: String? = nil,
        title: String? = "T",
        body: String? = "B"
    ) -> [AnyHashable: Any] {
        var info: [AnyHashable: Any] = [:]
        if let kind { info["kind"] = kind }
        if let tripId { info["tripId"] = tripId }
        info["aps"] = Self.aps(title: title, body: body)
        return info
    }

    /// The `.apns` fixtures and the `_debugPushes` bridge: a nested `data` map.
    private func nested(
        kind: String?,
        tripId: String? = nil,
        title: String? = "T",
        body: String? = "B"
    ) -> [AnyHashable: Any] {
        var data: [String: Any] = [:]
        if let kind { data["kind"] = kind }
        if let tripId { data["tripId"] = tripId }
        var info: [AnyHashable: Any] = ["aps": Self.aps(title: title, body: body)]
        if !data.isEmpty { info["data"] = data }
        return info
    }

    private static func aps(title: String?, body: String?) -> [String: Any] {
        var alert: [String: Any] = [:]
        if let title { alert["title"] = title }
        if let body { alert["body"] = body }
        return alert.isEmpty ? [:] : ["alert": alert]
    }

    private static let contractKinds = [
        "started", "tenMin", "leadTime", "slip", "arrived", "lost", "timeout",
        "cancelled", "didYouLeave", "armed", "noShow", "runningLate", "reply",
    ]

    // MARK: - Shape

    func testReadsKindTitleAndBodyFromTheFlattenedFcmShape() {
        let payload = PushPayload(userInfo: flattened(
            kind: "leadTime", tripId: "trip1",
            title: "Start walking now", body: "Mostafi is 3 min away"
        ))
        XCTAssertEqual(payload?.kind, .leadTime)
        XCTAssertEqual(payload?.rawKind, "leadTime")
        XCTAssertEqual(payload?.tripId, "trip1")
        XCTAssertEqual(payload?.title, "Start walking now")
        XCTAssertEqual(payload?.body, "Mostafi is 3 min away")
    }

    func testReadsKindTitleAndBodyFromTheNestedFixtureShape() {
        let payload = PushPayload(userInfo: nested(
            kind: "leadTime", tripId: "trip1",
            title: "Start walking now", body: "Mostafi is 3 min away"
        ))
        XCTAssertEqual(payload?.kind, .leadTime)
        XCTAssertEqual(payload?.tripId, "trip1")
        XCTAssertEqual(payload?.title, "Start walking now")
        XCTAssertEqual(payload?.body, "Mostafi is 3 min away")
    }

    func testTopLevelKindWinsOverANestedOne() {
        // Both present is not a shape the server produces; deciding it deterministically
        // is still cheaper than a heisenbug if it ever does.
        var info = flattened(kind: "arrived")
        info["data"] = ["kind": "slip"]
        XCTAssertEqual(PushPayload(userInfo: info)?.kind, .arrived)
    }

    func testAPayloadWithoutAKindIsNotOurs() {
        // Firebase Auth's app-verification silent push, a console campaign, anything else.
        XCTAssertNil(PushPayload(userInfo: flattened(kind: nil)))
        XCTAssertNil(PushPayload(userInfo: nested(kind: nil)))
        XCTAssertNil(PushPayload(userInfo: [:]))
        XCTAssertNil(PushPayload(userInfo: ["aps": ["content-available": 1]]))
    }

    func testAnEmptyOrWhitespaceKindIsNotOurs() {
        XCTAssertNil(PushPayload(userInfo: flattened(kind: "")))
        XCTAssertNil(PushPayload(userInfo: flattened(kind: "   ")))
        XCTAssertNil(PushPayload(userInfo: nested(kind: " \n ")))
    }

    func testMalformedInputNeverCrashes() {
        // Every one of these has been seen in the wild in some form.
        XCTAssertNil(PushPayload(userInfo: ["kind": 42]))
        XCTAssertNil(PushPayload(userInfo: ["data": "not-a-dictionary"]))
        XCTAssertNil(PushPayload(userInfo: ["data": ["kind": 7]]))
        XCTAssertNil(PushPayload(userInfo: ["aps": "not-a-dictionary"]))

        let noAps = PushPayload(userInfo: ["kind": "started"])
        XCTAssertEqual(noAps?.kind, .started)
        XCTAssertEqual(noAps?.title, "")
        XCTAssertEqual(noAps?.body, "")

        let apsWrongType = PushPayload(userInfo: ["kind": "started", "aps": ["alert": 12]])
        XCTAssertEqual(apsWrongType?.title, "")
        XCTAssertEqual(apsWrongType?.body, "")
    }

    func testTheShortStringAlertFormBecomesTheBody() {
        let payload = PushPayload(userInfo: ["kind": "reply", "aps": ["alert": "5 more min"]])
        XCTAssertEqual(payload?.title, "")
        XCTAssertEqual(payload?.body, "5 more min")
    }

    func testTripIdIsAbsentForNonTripPushes() {
        // ADDENDUM §D — every trip-scoped push carries data.tripId; non-trip pushes omit it.
        XCTAssertNil(PushPayload(userInfo: flattened(kind: "armed"))?.tripId)
        XCTAssertNil(PushPayload(userInfo: nested(kind: "armed"))?.tripId)
    }

    // MARK: - The thirteen kinds

    func testEveryKindInTheContractIsRecognisedInBothShapes() {
        // CLIENT_CONTRACT.md lines 50-52.
        for kind in Self.contractKinds {
            for info in [flattened(kind: kind), nested(kind: kind)] {
                let payload = PushPayload(userInfo: info)
                XCTAssertNotNil(payload, kind)
                XCTAssertTrue(payload!.isKnown, "\(kind) should be a known kind")
                XCTAssertEqual(payload!.rawKind, kind)
            }
        }
    }

    func testTheEnumAndTheContractListAgree() {
        XCTAssertEqual(PushKind.contractKinds.map(\.rawValue), Self.contractKinds)
        XCTAssertEqual(PushKind.contractKinds.count, 13)
        for kind in PushKind.contractKinds {
            XCTAssertEqual(PushKind(rawValue: kind.rawValue), kind)
            XCTAssertTrue(kind.isKnown)
        }
    }

    func testAnUnknownKindIsDeliveredButNotActedOn() {
        let stranger = PushPayload(userInfo: flattened(kind: "somethingNew"))
        XCTAssertNotNil(stranger)                       // still delivered and displayed
        XCTAssertFalse(stranger!.isKnown)               // but we do not act on it
        XCTAssertEqual(stranger!.kind, .unrecognised("somethingNew"))
        XCTAssertEqual(stranger!.rawKind, "somethingNew")
        XCTAssertFalse(stranger!.isUrgent)
        XCTAssertFalse(stranger!.raisesDriverNudge)
        XCTAssertFalse(stranger!.endsLiveActivity)
        XCTAssertEqual(PushRouter.destination(for: stranger!), .ignore)
    }

    // MARK: - Urgency (ADDENDUM §C)

    func testLeadTimeIsTheOnlyUrgentKind() {
        for kind in Self.contractKinds where kind != "leadTime" {
            let payload = PushPayload(userInfo: flattened(kind: kind))!
            XCTAssertFalse(payload.isUrgent, "\(kind) must not be urgent")
            XCTAssertEqual(payload.apnsInterruptionLevel, "active", kind)
        }
        let lead = PushPayload(userInfo: flattened(kind: "leadTime"))!
        XCTAssertTrue(lead.isUrgent)
        XCTAssertEqual(lead.apnsInterruptionLevel, "time-sensitive")
    }

    func testArrivedIsNotUrgent() {
        // The backend plan doc marked `arrived` urgent. ADDENDUM §C says that is wrong,
        // and this assertion is the reason nobody quietly re-adds it.
        XCTAssertFalse(PushPayload(userInfo: flattened(kind: "arrived"))!.isUrgent)
    }

    // MARK: - Behaviour flags

    func testTheDriverNudgeIsRaisedByExactlyOneKind() {
        for kind in Self.contractKinds {
            let payload = PushPayload(userInfo: flattened(kind: kind))!
            XCTAssertEqual(payload.raisesDriverNudge, kind == "didYouLeave", kind)
        }
    }

    func testKindsThatStartAndEndTheLiveActivity() {
        for kind in Self.contractKinds {
            let payload = PushPayload(userInfo: flattened(kind: kind))!
            XCTAssertEqual(payload.startsLiveActivity, kind == "started", kind)
            XCTAssertEqual(
                payload.endsLiveActivity,
                ["arrived", "cancelled", "timeout"].contains(kind),
                kind
            )
        }
    }

    // MARK: - Routing (PushRouter's pure half)

    func testEveryInFlightKindRoutesToTheTripScreenCarryingItsTripId() {
        for kind in ["started", "tenMin", "leadTime", "slip", "runningLate", "reply"] {
            let payload = PushPayload(userInfo: nested(kind: kind, tripId: "trip9"))!
            XCTAssertEqual(PushRouter.destination(for: payload), .trip(tripId: "trip9"), kind)
        }
    }

    func testEveryTerminalKindRoutesHome() {
        for kind in ["arrived", "cancelled", "timeout", "lost", "noShow", "armed"] {
            let payload = PushPayload(userInfo: nested(kind: kind, tripId: "trip9"))!
            XCTAssertEqual(PushRouter.destination(for: payload), .home, kind)
        }
    }

    func testDidYouLeaveRoutesToTheDriverNudgeSheet() {
        let payload = PushPayload(userInfo: nested(kind: "didYouLeave", tripId: "trip9"))!
        XCTAssertEqual(PushRouter.destination(for: payload), .driverNudge(tripId: "trip9"))
    }

    func testEveryContractKindHasADestination() {
        for kind in Self.contractKinds {
            let payload = PushPayload(userInfo: flattened(kind: kind, tripId: "t"))!
            XCTAssertNotEqual(
                PushRouter.destination(for: payload), .ignore,
                "\(kind) is a contract kind and must route somewhere"
            )
        }
    }

    // MARK: - The router's stateful half

    @MainActor
    func testHandleUpdatesTheRouterAndRaisesTheNudge() {
        let router = PushRouter()
        var ended = 0
        router.onEndLiveActivity = { ended += 1 }

        router.handle(PushPayload(userInfo: nested(kind: "slip", tripId: "t1"))!)
        XCTAssertEqual(router.destination, .trip(tripId: "t1"))
        XCTAssertFalse(router.showDriverNudge)
        XCTAssertEqual(ended, 0)

        router.handle(PushPayload(userInfo: nested(kind: "didYouLeave", tripId: "t1"))!)
        XCTAssertTrue(router.showDriverNudge)
        XCTAssertEqual(router.destination, .driverNudge(tripId: "t1"))

        router.dismissDriverNudge()
        XCTAssertFalse(router.showDriverNudge)

        router.handle(PushPayload(userInfo: nested(kind: "arrived", tripId: "t1"))!)
        XCTAssertEqual(router.destination, .home)
        XCTAssertEqual(ended, 1, "a terminal push must tear the Live Activity down")

        XCTAssertEqual(router.lastPayload?.kind, .arrived)
        router.clearDestination()
        XCTAssertEqual(router.destination, .ignore)
    }

    func testTheStaticFunnelRejectsAForeignPayloadAndAcceptsOurs() {
        // `handle(userInfo:)` is the ONE entry point every delivery path uses; its return
        // value is what `didReceiveRemoteNotification` reports back to iOS.
        XCTAssertFalse(PushRouter.handle(userInfo: ["aps": ["content-available": 1]]))
        XCTAssertTrue(PushRouter.handle(userInfo: nested(kind: "started", tripId: "t1")))
    }
}
