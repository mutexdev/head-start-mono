// ios/HeadstartTests/PolylineTests.swift
import XCTest
@testable import Headstart

// The plan doc's version of this file pulls in CoreLocation because its decoder returned
// [CLLocationCoordinate2D]. This batch is Foundation-only, so the decoder returns
// [HSCoordinate] with the same `latitude`/`longitude` member names and the assertions
// below are otherwise unchanged.

final class PolylineTests: XCTestCase {

    func testDecodesTheGoogleReferenceExample() {
        // The example from Google's encoded-polyline documentation, precision 5.
        let points = decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].latitude, 38.5, accuracy: 0.0001)
        XCTAssertEqual(points[0].longitude, -120.2, accuracy: 0.0001)
        XCTAssertEqual(points[1].latitude, 40.7, accuracy: 0.0001)
        XCTAssertEqual(points[1].longitude, -120.95, accuracy: 0.0001)
        XCTAssertEqual(points[2].latitude, 43.252, accuracy: 0.0001)
        XCTAssertEqual(points[2].longitude, -126.453, accuracy: 0.0001)
    }

    func testAnEmptyStringDecodesToNoPoints() {
        XCTAssertTrue(decodePolyline("").isEmpty)
    }

    func testATruncatedStringDoesNotCrashAndReturnsWhatItGot() {
        // A partial write must not take the trip screen down with it.
        let points = decodePolyline("_p~iF~ps|U_ulL")
        XCTAssertLessThanOrEqual(points.count, 2)
    }

    func testCharactersOutsideTheEncodingAreIgnoredRatherThanFatal() {
        XCTAssertNoThrow(decodePolyline("!!!"))
        XCTAssertTrue(decodePolyline("!!!").isEmpty)
    }
}
