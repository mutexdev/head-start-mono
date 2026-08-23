// ios/HeadstartTests/ThemeTests.swift
import XCTest
import SwiftUI
import UIKit
@testable import Headstart

final class HexColorTests: XCTestCase {

    func testSplitsHexIntoZeroToOneComponents() {
        // (hex, r, g, b) — the tokens from design/README.md
        let table: [(UInt32, Double, Double, Double)] = [
            (0x000000, 0, 0, 0),
            (0xFFFFFF, 1, 1, 1),
            (0x3AD693, 58.0 / 255, 214.0 / 255, 147.0 / 255),   // Go
            (0xF0A13C, 240.0 / 255, 161.0 / 255, 60.0 / 255),   // Headstart
            (0x15171B, 21.0 / 255, 23.0 / 255, 27.0 / 255),     // Base
        ]
        for (hex, r, g, b) in table {
            let c = HexColor.components(hex)
            XCTAssertEqual(c.r, r, accuracy: 0.0001, "red of \(String(hex, radix: 16))")
            XCTAssertEqual(c.g, g, accuracy: 0.0001, "green of \(String(hex, radix: 16))")
            XCTAssertEqual(c.b, b, accuracy: 0.0001, "blue of \(String(hex, radix: 16))")
        }
    }

    func testIgnoresBitsAboveTheLowTwentyFour() {
        XCTAssertEqual(HexColor.components(0xFF3AD693).r, 58.0 / 255, accuracy: 0.0001)
    }

    func testTokenColoursRoundTripThroughUIColor() {
        // Three spot checks that Color(hex:) actually produces the token.
        let cases: [(Color, UInt32)] = [
            (HS.go, 0x3AD693),
            (HS.headstart, 0xF0A13C),
            (HS.delayed, 0xEF6F52),
        ]
        for (color, hex) in cases {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            let want = HexColor.components(hex)
            XCTAssertEqual(Double(r), want.r, accuracy: 0.01)
            XCTAssertEqual(Double(g), want.g, accuracy: 0.01)
            XCTAssertEqual(Double(b), want.b, accuracy: 0.01)
            XCTAssertEqual(Double(a), 1.0, accuracy: 0.01)
        }
    }
}

final class TypographyTests: XCTestCase {

    func testArchivoFacesAreBundledAndRegistered() {
        XCTAssertTrue(
            HSFont.isArchivoAvailable,
            "Archivo is not registered. Add the four static .ttf files to the Headstart target and list them under UIAppFonts."
        )
        for name in ["Archivo-Regular", "Archivo-Medium", "Archivo-SemiBold", "Archivo-Bold"] {
            XCTAssertNotNil(UIFont(name: name, size: 17), "missing face \(name)")
        }
    }

    func testPostScriptNameForEachWeight() {
        XCTAssertEqual(HSFont.faceName(for: .regular), "Archivo-Regular")
        XCTAssertEqual(HSFont.faceName(for: .medium), "Archivo-Medium")
        XCTAssertEqual(HSFont.faceName(for: .semibold), "Archivo-SemiBold")
        XCTAssertEqual(HSFont.faceName(for: .bold), "Archivo-Bold")
        // Anything else collapses onto the nearest bundled face.
        XCTAssertEqual(HSFont.faceName(for: .heavy), "Archivo-Bold")
        XCTAssertEqual(HSFont.faceName(for: .light), "Archivo-Regular")
    }
}

final class MetricsTests: XCTestCase {
    func testControlMetricsMatchTheContract() {
        // CLIENT_CONTRACT.md §Design tokens: controls 56 pt, nothing interactive under 44.
        XCTAssertEqual(HS.controlHeight, 56)
        XCTAssertEqual(HS.minTouchTarget, 44)
        XCTAssertEqual(HS.screenPadding, 26)
        XCTAssertEqual(HS.Radius.control, 14)
        XCTAssertEqual(HS.Radius.card, 16)
        XCTAssertEqual(HS.Radius.sheet, 26)
    }
}
