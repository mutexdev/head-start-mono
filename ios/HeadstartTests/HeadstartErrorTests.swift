// ios/HeadstartTests/HeadstartErrorTests.swift
import XCTest
@testable import Headstart

final class HeadstartErrorTests: XCTestCase {

    func testEveryContractErrorCodeMapsToItsOwnCase() {
        // CLIENT_CONTRACT.md: "Error codes returned as the callable's message"
        let table: [(String, HeadstartError)] = [
            ("not-paired", .notPaired),
            ("trip-active", .tripActive),
            ("spot-not-found", .spotNotFound),
            ("bad-code", .badCode),
            ("own-code", .ownCode),
            ("driver-only", .driverOnly),
            ("trip-not-found", .tripNotFound),
            ("bad-coords", .badCoords),
            ("bad-name", .badName),
            ("bad-token", .badToken),
        ]
        for (message, expected) in table {
            XCTAssertEqual(headstartErrorFor(message), expected, message)
        }
    }

    func testTheTwoCodesOutsideTheContractsTenAreAlsoMapped() {
        // CLIENT_CONTRACT_ADDENDUM.md §O, and the spec's §9 rate limiting.
        XCTAssertEqual(headstartErrorFor("bad-reply"), .badReply)
        XCTAssertEqual(headstartErrorFor("rate-limited"), .rateLimited)
    }

    func testSurroundingWhitespaceAndWrapperTextStillResolve() {
        XCTAssertEqual(headstartErrorFor("  bad-code  "), .badCode)
        XCTAssertEqual(headstartErrorFor("INVALID_ARGUMENT: bad-code"), .badCode)
    }

    func testUnauthenticatedAndNetworkBeatAnyMessage() {
        XCTAssertEqual(headstartErrorFor("bad-code", isUnauthenticated: true), .unauthenticated)
        XCTAssertEqual(headstartErrorFor("bad-code", isNetwork: true), .offline)
    }

    func testAnUnrecognisedMessageBecomesUnknownAndKeepsTheRawCode() {
        let e = headstartErrorFor("kaboom")
        XCTAssertEqual(e, .unknown("kaboom"))
        XCTAssertEqual(e.code, "kaboom")
        XCTAssertEqual(e.userMessage, "Something went wrong. Try again.")
    }

    func testAnEmptyOrNilMessageBecomesUnknown() {
        XCTAssertEqual(headstartErrorFor(nil), .unknown("unknown"))
        XCTAssertEqual(headstartErrorFor(""), .unknown("unknown"))
    }

    func testEveryCaseHasASentenceAUserCanRead() {
        let all: [HeadstartError] = [
            .notPaired, .tripActive, .spotNotFound, .badCode, .ownCode, .driverOnly,
            .tripNotFound, .badCoords, .badName, .badToken, .badReply, .rateLimited,
            .unauthenticated, .offline,
        ]
        for e in all {
            XCTAssertFalse(e.userMessage.isEmpty, e.code)
            XCTAssertTrue(e.userMessage.first!.isUppercase, e.code)
            XCTAssertFalse(e.userMessage.contains("-"), "\(e.code) leaks a wire code to the user")
        }
    }

    func testAnNSErrorFromTheFunctionsSdkIsAdapted() {
        // FunctionsErrorDomain == "com.firebase.functions"; 16 == unauthenticated,
        // 14 == unavailable — the two transport facts that outrank the message.
        let notFound = NSError(
            domain: "com.firebase.functions",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "spot-not-found"]
        )
        XCTAssertEqual(notFound.asHeadstartError(), .spotNotFound)

        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertEqual(offline.asHeadstartError(), .offline)

        // A HeadstartError thrown by our own code passes straight through.
        let already: Error = HeadstartError.ownCode
        XCTAssertEqual(already.asHeadstartError(), .ownCode)
    }

    func testTheTwoTransportStatusesOutrankTheCallableMessage() {
        let unauthenticated = NSError(
            domain: kFunctionsErrorDomain,
            code: CallableStatus.unauthenticated,
            userInfo: [NSLocalizedDescriptionKey: "bad-code"]
        )
        XCTAssertEqual(unauthenticated.asHeadstartError(), .unauthenticated)

        let unavailable = NSError(
            domain: kFunctionsErrorDomain,
            code: CallableStatus.unavailable,
            userInfo: [NSLocalizedDescriptionKey: "bad-code"]
        )
        XCTAssertEqual(unavailable.asHeadstartError(), .offline)

        let deadline = NSError(
            domain: kFunctionsErrorDomain,
            code: CallableStatus.deadlineExceeded,
            userInfo: [NSLocalizedDescriptionKey: "bad-code"]
        )
        XCTAssertEqual(deadline.asHeadstartError(), .offline)
    }
}
