// ios/Headstart/Push/PushPayload.swift
//
// One arriving alert, reduced to the fields CLIENT_CONTRACT.md guarantees. PURE — no
// UIKit, no UserNotifications, no Firebase — so every routing rule below is unit-tested
// rather than eyeballed on a device that this machine does not have.
//
// THREE DELIVERY SHAPES REACH THIS PARSER, and they disagree about where `kind` lives:
//
//   1. Real FCM -> APNs. FCM flattens the `data` map onto the ROOT of the APNs payload,
//      so `userInfo["kind"]` is a top-level string.
//   2. `xcrun simctl push <udid> com.mutexdev.headstart ios/fixtures/push/<kind>.apns`.
//      The fixtures carry a NESTED `data` dictionary, exactly like the server's
//      `_debugPushes` document, because that is the shape the contract writes down.
//   3. The `#if DEBUG` `_debugPushes` bridge (CLIENT_CONTRACT_ADDENDUM.md, "Emulator
//      contract"), which rebuilds a userInfo dictionary from a Firestore row.
//
// So the parser reads top-level `kind` first and falls back to `data.kind`. Both paths
// are covered by PushPayloadTests; neither is theoretical.
//
// UNKNOWN KINDS ARE NOT ERRORS. A server that ships a fourteenth kind must not crash a
// client that predates it: an unrecognised string parses to `.unrecognised(_)`, is still
// delivered and displayed by iOS, and is simply not acted on.

import Foundation

/// Every `data.kind` in CLIENT_CONTRACT.md lines 50-52, plus the open case that keeps a
/// future server additive rather than breaking.
public enum PushKind: Hashable, Sendable {
    case started
    case tenMin
    case leadTime
    case slip
    case arrived
    case lost
    case timeout
    case cancelled
    case didYouLeave
    case armed
    case noShow
    case runningLate
    case reply
    /// A kind this build does not know. Rendered by iOS, ignored by the router.
    case unrecognised(String)

    /// The thirteen contract kinds, in contract order. `ios/fixtures/push/` holds one
    /// `.apns` fixture per entry.
    public static let contractKinds: [PushKind] = [
        .started, .tenMin, .leadTime, .slip, .arrived, .lost, .timeout,
        .cancelled, .didYouLeave, .armed, .noShow, .runningLate, .reply,
    ]

    public init(rawValue: String) {
        switch rawValue {
        case "started": self = .started
        case "tenMin": self = .tenMin
        case "leadTime": self = .leadTime
        case "slip": self = .slip
        case "arrived": self = .arrived
        case "lost": self = .lost
        case "timeout": self = .timeout
        case "cancelled": self = .cancelled
        case "didYouLeave": self = .didYouLeave
        case "armed": self = .armed
        case "noShow": self = .noShow
        case "runningLate": self = .runningLate
        case "reply": self = .reply
        default: self = .unrecognised(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .started: "started"
        case .tenMin: "tenMin"
        case .leadTime: "leadTime"
        case .slip: "slip"
        case .arrived: "arrived"
        case .lost: "lost"
        case .timeout: "timeout"
        case .cancelled: "cancelled"
        case .didYouLeave: "didYouLeave"
        case .armed: "armed"
        case .noShow: "noShow"
        case .runningLate: "runningLate"
        case .reply: "reply"
        case .unrecognised(let raw): raw
        }
    }

    public var isKnown: Bool {
        if case .unrecognised = self { return false }
        return true
    }
}

/// One notification, parsed.
public struct PushPayload: Equatable, Sendable {

    public let kind: PushKind
    /// ADDENDUM §D — every trip-scoped push carries `data.tripId`. Non-trip pushes omit it.
    public let tripId: String?
    public let title: String
    public let body: String

    public init(kind: PushKind, tripId: String? = nil, title: String = "", body: String = "") {
        self.kind = kind
        self.tripId = tripId
        self.title = title
        self.body = body
    }

    /// nil when the dictionary is not one of ours — a Firebase Auth app-verification
    /// silent push, a console campaign with no `data.kind`, anything else. Never traps.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let raw = Self.string(userInfo, "kind") else { return nil }
        self.kind = PushKind(rawValue: raw)
        self.tripId = Self.string(userInfo, "tripId")

        let fallbackTitle = Self.string(userInfo, "title") ?? ""
        let fallbackBody = Self.string(userInfo, "body") ?? ""
        let alert: Any = Self.dictionary(userInfo["aps"])?["alert"] ?? ""
        if let alert = Self.dictionary(alert) {
            self.title = Self.clean(alert["title"]) ?? fallbackTitle
            self.body = Self.clean(alert["body"]) ?? fallbackBody
        } else if let text = Self.clean(alert) {
            // The short `"alert": "text"` APNs form carries no separate title.
            self.title = fallbackTitle
            self.body = text
        } else {
            self.title = fallbackTitle
            self.body = fallbackBody
        }
    }

    // MARK: - Routing rules (CLIENT_CONTRACT.md + ADDENDUM §C)

    public var rawKind: String { kind.rawValue }
    public var isKnown: Bool { kind.isKnown }

    /// ADDENDUM §C — `leadTime` is the ONLY urgent kind. `arrived` is not; the backend
    /// plan doc said otherwise and was wrong. The server already stamps
    /// `interruption-level` on the wire; this flag exists for our own UI decisions and
    /// for the `_debugPushes` bridge, which has to re-derive it.
    public var isUrgent: Bool { kind == .leadTime }

    /// Mirrors the server's `interruptionLevelFor` exactly (functions/src/io/push.ts).
    public var apnsInterruptionLevel: String { isUrgent ? "time-sensitive" : "active" }

    /// The driver-side sheet from `design/DriverNudge.dc.html`.
    public var raisesDriverNudge: Bool { kind == .didYouLeave }

    /// The receiver's Live Activity begins when the trip starts driving.
    public var startsLiveActivity: Bool { kind == .started }

    /// …and is torn down by any terminal outcome that reaches us as a push.
    public var endsLiveActivity: Bool {
        kind == .arrived || kind == .cancelled || kind == .timeout
    }

    // MARK: - Dictionary reading
    //
    // Firestore, PropertyList and NSDictionary all hand back slightly different key
    // types, so everything is read through `[AnyHashable: Any]`.

    private static func dictionary(_ value: Any?) -> [AnyHashable: Any]? {
        if let d = value as? [AnyHashable: Any] { return d }
        if let d = value as? [String: Any] { return d }
        return nil
    }

    /// Top-level first (real FCM flattens `data` onto the root), then the nested `data`
    /// map (simctl fixtures and `_debugPushes` rows). Whitespace-only is treated as absent.
    private static func string(_ userInfo: [AnyHashable: Any], _ key: String) -> String? {
        if let value = clean(userInfo[key]) { return value }
        if let data = dictionary(userInfo["data"]), let value = clean(data[key]) { return value }
        return nil
    }

    private static func clean(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
