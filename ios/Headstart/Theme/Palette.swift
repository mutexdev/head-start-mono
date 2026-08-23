// ios/Headstart/Theme/Palette.swift
import SwiftUI

/// Splits a `0xRRGGBB` literal into sRGB components. Pure, so it is unit-tested.
public enum HexColor {
    public static func components(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        (
            Double((hex >> 16) & 0xFF) / 255.0,
            Double((hex >> 8) & 0xFF) / 255.0,
            Double(hex & 0xFF) / 255.0
        )
    }
}

public extension Color {
    /// `Color(hex: 0x3AD693)`. M1 is dark-only (CLIENT_CONTRACT.md §Design tokens),
    /// so these are literals rather than asset-catalog colour sets with two variants.
    init(hex: UInt32, opacity: Double = 1) {
        let c = HexColor.components(hex)
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: opacity)
    }
}

/// Every design token from CLIENT_CONTRACT.md §Design tokens.
/// Nothing in the app may hard-code a colour.
public enum HS {
    // Surfaces
    public static let base = Color(hex: 0x15171B)
    public static let card = Color(hex: 0x1E2126)
    public static let raised = Color(hex: 0x262A30)
    public static let line = Color(hex: 0x31363D)

    // Text
    public static let text = Color(hex: 0xF2F4F7)
    public static let text2 = Color(hex: 0xA8B0BA)
    public static let text3 = Color(hex: 0x6D7681)

    // Semantic
    /// Driver acts — the "I'm coming" button, the sharing dot, progress fill.
    public static let go = Color(hex: 0x3AD693)
    public static let goInk = Color(hex: 0x0C1C14)
    /// Walk out now — the receiver's headstart, the lead-time alert.
    public static let headstart = Color(hex: 0xF0A13C)
    public static let headstartInk = Color(hex: 0x241804)
    /// Stay inside — traffic slip, cancel, destructive.
    public static let delayed = Color(hex: 0xEF6F52)

    // Map panel (ReceiverTrip, SpotEdit)
    public static let mapBase = Color(hex: 0x1A1D22)
    public static let mapRoad = Color(hex: 0x23272D)
    public static let mapMinor = Color(hex: 0x20242A)
    public static let mapBlock = Color(hex: 0x1E2228)

    // Tinted fills used by the artboards
    public static let headstartWash = Color(hex: 0xF0A13C, opacity: 0.10)
    public static let headstartEdge = Color(hex: 0xF0A13C, opacity: 0.40)
    public static let headstartIconWash = Color(hex: 0xF0A13C, opacity: 0.14)
    public static let delayedEdge = Color(hex: 0xEF6F52, opacity: 0.55)

    // Metrics
    public static let controlHeight: CGFloat = 56
    public static let minTouchTarget: CGFloat = 44
    public static let screenPadding: CGFloat = 26

    public enum Radius {
        public static let control: CGFloat = 14
        public static let chip: CGFloat = 23
        public static let card: CGFloat = 16
        public static let bigCard: CGFloat = 22
        public static let sheet: CGFloat = 26
    }
}
