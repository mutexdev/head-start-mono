// ios/HeadstartTests/PartnerNameTests.swift
//
// These tests replace Task 10's push-title-parsing table, which the plan doc's own
// AMENDMENT supersedes: the backend now denormalises both display names onto
// `pairs/{pairId}.memberNames`, so the name is a dictionary lookup and there is nothing to
// parse. What survives from Task 10 is the shape of the contract — a resolved name, and a
// neutral fallback that never leaves a sentence half-written.
//
// Android must produce the same string for every row below.

import XCTest
@testable import Headstart

private let names = ["d1": "Mostafi", "r1": "Sara"]

private func pair(
    members: [String] = ["d1", "r1"],
    memberNames: [String: String]? = names,
    status: String = "active"
) -> Pair {
    var data: [String: Any] = [
        "members": members,
        "status": status,
        "inviteCode": "K7M2QP",
        "createdBy": "d1",
        "createdAt": 1_700_000_000_000,
    ]
    if let memberNames { data["memberNames"] = memberNames }
    return Pair(id: "p1", data: data)!
}

final class PartnerNameTests: XCTestCase {

    func testResolvesTheOtherMembersNameFromTheMap() {
        XCTAssertEqual(PartnerName.resolve(memberNames: names, otherUid: "r1"), "Sara")
        XCTAssertEqual(PartnerName.resolve(memberNames: names, otherUid: "d1"), "Mostafi")
    }

    func testResolvesFromThePairDocumentForEitherSide() {
        XCTAssertEqual(PartnerName.resolve(pair: pair(), selfUid: "d1"), "Sara")
        XCTAssertEqual(PartnerName.resolve(pair: pair(), selfUid: "r1"), "Mostafi")
    }

    /// The whole table of ways the name can be unavailable. Every one of them must produce
    /// the same neutral phrase — never an empty string, never "nil", never a uid.
    func testEveryUnresolvableCaseFallsBackToTheNeutralPhrase() {
        let table: [(String, String)] = [
            ("key missing", PartnerName.resolve(memberNames: names, otherUid: "nobody")),
            ("empty name", PartnerName.resolve(memberNames: ["r1": ""], otherUid: "r1")),
            ("whitespace only", PartnerName.resolve(memberNames: ["r1": "   \n"], otherUid: "r1")),
            ("no map at all", PartnerName.resolve(memberNames: nil, otherUid: "r1")),
            ("empty map", PartnerName.resolve(memberNames: [:], otherUid: "r1")),
            ("no other uid", PartnerName.resolve(memberNames: names, otherUid: nil)),
            ("empty other uid", PartnerName.resolve(memberNames: names, otherUid: "")),
            ("no pair yet", PartnerName.resolve(pair: nil, selfUid: "d1")),
        ]
        for (label, resolved) in table {
            XCTAssertEqual(resolved, "Your partner", label)
        }
    }

    /// A pending pair has one member, so there is no other uid to look up yet.
    func testAPendingPairFallsBack() {
        let pending = pair(members: ["d1"], memberNames: ["d1": "Mostafi"], status: "pending")
        XCTAssertEqual(PartnerName.resolve(pair: pending, selfUid: "d1"), "Your partner")
        XCTAssertFalse(PartnerName.isKnown(memberNames: pending.memberNames, otherUid: pending.other(than: "d1")))
    }

    /// The backend denormalises whatever the person typed; the client only trims.
    func testTheNameIsTrimmedButNotOtherwiseTouched() {
        XCTAssertEqual(PartnerName.resolve(memberNames: ["r1": "  Sara Khan  "], otherUid: "r1"), "Sara Khan")
        XCTAssertEqual(PartnerName.resolve(memberNames: ["r1": "sara"], otherUid: "r1"), "sara")
        XCTAssertEqual(PartnerName.resolve(memberNames: ["r1": "Sara 🚗"], otherUid: "r1"), "Sara 🚗")
        let long = String(repeating: "a", count: 120)
        XCTAssertEqual(PartnerName.resolve(memberNames: ["r1": long], otherUid: "r1"), long)
    }

    func testShortFormIsUsableMidSentence() {
        XCTAssertEqual(PartnerName.short(memberNames: names, otherUid: "r1"), "Sara")
        XCTAssertEqual(PartnerName.short(memberNames: names, otherUid: "nobody"), "they")
        XCTAssertEqual(PartnerName.short(memberNames: nil, otherUid: nil), "they")
        XCTAssertEqual(PartnerName.short(pair: pair(), selfUid: "d1"), "Sara")
        XCTAssertEqual(PartnerName.short(pair: nil, selfUid: "d1"), "they")
    }

    func testIsKnownDistinguishesARealNameFromTheFallback() {
        XCTAssertTrue(PartnerName.isKnown(memberNames: names, otherUid: "r1"))
        XCTAssertFalse(PartnerName.isKnown(memberNames: ["r1": " "], otherUid: "r1"))
        XCTAssertFalse(PartnerName.isKnown(memberNames: nil, otherUid: "r1"))
    }

    /// The fallback is a sentence-initial phrase, because every artboard that can show it
    /// starts a sentence with it ("Your partner is driving").
    func testTheFallbackReadsAsTheStartOfASentence() {
        XCTAssertEqual(PartnerName.fallback, "Your partner")
        XCTAssertTrue(PartnerName.fallback.first!.isUppercase)
        XCTAssertEqual(PartnerName.shortFallback, "they")
    }
}
