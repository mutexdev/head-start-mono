// ios/HeadstartTests/PhoneNumberTests.swift
//
// E.164 assembly and the two field sanitisers are the only pure logic in Task 7 — everything
// else in the auth batch is a Firebase call or layout. So that is what gets tested.

import XCTest
@testable import Headstart

final class PhoneNumberTests: XCTestCase {

    func testAssemblesE164FromADialCodeAndWhateverTheUserTyped() {
        let table: [(String, String, String)] = [
            ("+880", "1712 345678", "+8801712345678"),
            ("+880", "01712345678", "+8801712345678"),   // national trunk zero is stripped
            ("+880", "  1712-345678 ", "+8801712345678"),
            ("+1", "(415) 555-0123", "+14155550123"),
            ("880", "1712345678", "+8801712345678"),     // dial code without the plus
            // The two canonical Auth-emulator test numbers must survive normalisation
            // untouched, or the whole emulator sign-in path is untestable.
            ("+1", "5555550100", "+15555550100"),
            ("+1", "5555550101", "+15555550101"),
        ]
        for (dial, national, expected) in table {
            XCTAssertEqual(PhoneNumber.e164(dialCode: dial, national: national), expected, national)
        }
    }

    func testRejectsNumbersThatCannotBeReal() {
        XCTAssertNil(PhoneNumber.e164(dialCode: "+880", national: ""))
        XCTAssertNil(PhoneNumber.e164(dialCode: "+880", national: "12345"))     // too short
        XCTAssertNil(PhoneNumber.e164(dialCode: "+880", national: "000000"))    // all trunk zeros
        XCTAssertNil(PhoneNumber.e164(dialCode: "+880", national: "123456789012345"))  // too long
        XCTAssertNil(PhoneNumber.e164(dialCode: "", national: "1712345678"))
        XCTAssertNil(PhoneNumber.e164(dialCode: "+", national: "1712345678"))
    }

    func testOnlyDigitsAndAtMostSixCharactersReachTheCodeField() {
        XCTAssertEqual(PhoneNumber.sanitizeOtp("1a2b3c4d5e6f7"), "123456")
        XCTAssertEqual(PhoneNumber.sanitizeOtp("49 2"), "492")
        XCTAssertEqual(PhoneNumber.sanitizeOtp(""), "")
    }

    func testInviteCodesAreUppercasedAndRestrictedToTheServerAlphabet() {
        // Server alphabet: ABCDEFGHJKLMNPQRSTUVWXYZ23456789 (no I, O, 0, 1).
        XCTAssertEqual(PhoneNumber.sanitizeInviteCode("k7m2qp"), "K7M2QP")
        XCTAssertEqual(PhoneNumber.sanitizeInviteCode("K7-M2 QP"), "K7M2QP")
        XCTAssertEqual(PhoneNumber.sanitizeInviteCode("IO01K7M2QP"), "K7M2QP")
        XCTAssertEqual(PhoneNumber.sanitizeInviteCode("K7M2QPZZZ"), "K7M2QP")
    }

    /// Pasting the whole share sentence from ADDENDUM §N must still yield the code, which is
    /// why that sentence leads with the bare code.
    func testPastingTheShareSentenceStillYieldsTheCode() {
        XCTAssertEqual(
            PhoneNumber.sanitizeInviteCode("K7M2QP — headstart://pair/K7M2QP"),
            "K7M2QP"
        )
    }

    func testCompletenessMirrorsTheServerCodeLength() {
        XCTAssertTrue(PhoneNumber.isCompleteInviteCode("k7m2qp"))
        XCTAssertFalse(PhoneNumber.isCompleteInviteCode("K7M2Q"))
        XCTAssertFalse(PhoneNumber.isCompleteInviteCode("IIIIII"))
    }

    /// Every character the server can mint must survive the sanitiser unchanged, and none of
    /// the four look-alikes may.
    func testTheAlphabetItselfRoundTripsAndTheLookAlikesAreDropped() {
        for character in PhoneNumber.inviteAlphabet {
            XCTAssertEqual(PhoneNumber.sanitizeInviteCode(String(character)), String(character))
        }
        for character in "IO01" {
            XCTAssertEqual(PhoneNumber.sanitizeInviteCode(String(character)), "")
        }
    }
}
