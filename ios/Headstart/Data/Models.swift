// ios/Headstart/Data/Models.swift
//
// Firestore hands back `[String: Any]` with `NSNumber` boxes, and omits every field the
// server has not written yet. Hand-written mappers make that explicit and — unlike
// `Codable` — let a partly-written trip document still render. They are pure functions
// over dictionaries, so they are unit-tested with no Firebase linkage: this file is
// Foundation-only on purpose.
//
// Two contract rules are encoded in the TYPE SYSTEM here, not in prose:
//
//  1. CLIENT_CONTRACT.md line 39 / ADDENDUM §H — "Receivers render `receiverView` only —
//     never `lastPos`". `Trip` therefore has NO top-level `lastPos` property at all. The
//     field exists on the server document and will be present in every snapshot the
//     receiver's listener receives; it is simply unreachable from Swift, so no screen can
//     read it by accident. Arrival is a server decision (contract line 87), so the client
//     never needs it. The server's fuzzed projection inside `receiverView` IS renderable,
//     and is exposed as `ReceiverView.point` — deliberately NOT named after the server key
//     it is read from, so that `grep -rn 'lastPos' ios/Headstart/UI/Receiver/` stays empty
//     even when the receiver map draws the dot.
//
//  2. ADDENDUM §I — `alerts` carries exactly six fields. The spec's seventh,
//     `lastSlipEtaSec`, is server-internal and is not modelled. Every flag is absent until
//     it first fires, so every one of them defaults rather than trapping.

import Foundation

// MARK: - Dictionary readers
// Firestore boxes every number as NSNumber and omits fields the server has not written.

private func num(_ value: Any?) -> Double? {
    if let n = value as? NSNumber {
        // `true`/`false` come back as NSNumber too. A boolean is not a number here:
        // reading `alerts.started` as 1.0 would silently turn a flag into a count.
        if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
        return n.doubleValue
    }
    if let d = value as? Double { return d }
    if let i = value as? Int { return Double(i) }
    return nil
}

private func int(_ value: Any?) -> Int? { num(value).map { Int($0.rounded()) } }
private func long(_ value: Any?) -> Int64? { num(value).map { Int64($0.rounded()) } }
private func str(_ value: Any?) -> String? { value as? String }
private func bool(_ value: Any?) -> Bool? { value as? Bool }
private func dict(_ value: Any?) -> [String: Any]? { value as? [String: Any] }

private func stringMap(_ value: Any?) -> [String: String] {
    guard let raw = value as? [String: Any] else { return [:] }
    return raw.compactMapValues { $0 as? String }
}

// MARK: - Small value types

public struct LatLng: Equatable, Sendable {
    public let lat: Double
    public let lng: Double

    public init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }

    init?(_ data: [String: Any]?) {
        guard let data, let lat = num(data["lat"]), let lng = num(data["lng"]) else { return nil }
        self.init(lat: lat, lng: lng)
    }
}

/// `trip.bands` and `startTrip`'s response body. Metres.
public struct Bands: Codable, Equatable, Sendable {
    public let far: Double
    public let near: Double
    public let lead: Double

    public init(far: Double, near: Double, lead: Double) {
        self.far = far
        self.near = near
        self.lead = lead
    }

    init?(_ data: [String: Any]?) {
        guard let data,
              let far = num(data["far"]),
              let near = num(data["near"]),
              let lead = num(data["lead"]) else { return nil }
        self.init(far: far, near: near, lead: lead)
    }
}

/// The spot snapshotted onto the trip document — `spot{lat,lng,radiusM,name}`.
public struct TripSpot: Equatable, Sendable {
    public let lat: Double
    public let lng: Double
    public let radiusM: Double
    public let name: String

    public init(lat: Double, lng: Double, radiusM: Double, name: String) {
        self.lat = lat
        self.lng = lng
        self.radiusM = radiusM
        self.name = name
    }

    init?(_ data: [String: Any]?) {
        guard let data,
              let lat = num(data["lat"]),
              let lng = num(data["lng"]),
              let name = str(data["name"]) else { return nil }
        self.lat = lat
        self.lng = lng
        self.radiusM = num(data["radiusM"]) ?? SpotLimits.defaultRadiusM
        self.name = name
    }

    public var coordinate: LatLng { LatLng(lat: lat, lng: lng) }
}

public struct TripEta: Equatable, Sendable {
    public let seconds: Int
    public let updatedAt: Int64
    public let approximate: Bool

    public init(seconds: Int, updatedAt: Int64, approximate: Bool) {
        self.seconds = seconds
        self.updatedAt = updatedAt
        self.approximate = approximate
    }

    init?(_ data: [String: Any]?) {
        guard let data, let seconds = int(data["seconds"]) else { return nil }
        self.seconds = seconds
        self.updatedAt = long(data["updatedAt"]) ?? 0
        self.approximate = bool(data["approximate"]) ?? false
    }
}

/// The projection a receiver renders — and the ONLY position source a receiver surface
/// may touch. Fuzzy mode is enforced by the server omitting the point from this
/// projection, so there is nothing for the client to decide.
public struct ReceiverView: Equatable, Sendable {
    public let etaSeconds: Int
    public let progressPct: Int
    /// Read from the server key `"lastPos"` inside `receiverView`, and deliberately given
    /// a different Swift name — see the header note. Nil in fuzzy mode.
    public let point: LatLng?

    public init(etaSeconds: Int, progressPct: Int, point: LatLng?) {
        self.etaSeconds = etaSeconds
        self.progressPct = progressPct
        self.point = point
    }

    init?(_ data: [String: Any]?) {
        guard let data, let eta = int(data["etaSeconds"]) else { return nil }
        self.etaSeconds = eta
        self.progressPct = int(data["progressPct"]) ?? 0
        self.point = LatLng(dict(data["lastPos"]))
    }
}

/// ADDENDUM §I — exactly these six. Every one is absent until it first fires.
public struct TripAlerts: Equatable, Sendable {
    public var started = false
    public var tenMin = false
    public var leadTime = false
    public var arrived = false
    public var didYouLeave = false
    public var slipCount = 0

    public init() {}

    init(_ data: [String: Any]?) {
        guard let data else { return }
        started = bool(data["started"]) ?? false
        tenMin = bool(data["tenMin"]) ?? false
        leadTime = bool(data["leadTime"]) ?? false
        arrived = bool(data["arrived"]) ?? false
        didYouLeave = bool(data["didYouLeave"]) ?? false
        slipCount = int(data["slipCount"]) ?? 0
    }
}

public enum TripState: String, Sendable, CaseIterable {
    case armed, driving, arrived, cancelled, timeout, lost
}

public enum TripRole: String, Sendable, Equatable {
    case driver, receiver
}

/// Server-side clamps from CLIENT_CONTRACT.md line 15 and ADDENDUM §K, mirrored on the
/// client so a person never sees a raw callable error. `Callables` applies these at the
/// wire boundary; the spot editor constrains its controls to the same ranges.
public enum SpotLimits {
    public static let leadTimeMinRange = 1...30
    public static let radiusMRange = 50.0...500.0
    public static let extraMinRange = 1...60
    public static let defaultRadiusM = 100.0
    public static let defaultLeadTimeMin = 3

    public static func clampLeadTimeMin(_ v: Int) -> Int {
        min(max(v, leadTimeMinRange.lowerBound), leadTimeMinRange.upperBound)
    }

    public static func clampRadiusM(_ v: Double) -> Double {
        min(max(v, radiusMRange.lowerBound), radiusMRange.upperBound)
    }

    public static func clampExtraMin(_ v: Int) -> Int {
        min(max(v, extraMinRange.lowerBound), extraMinRange.upperBound)
    }
}

// MARK: - Documents

/// `pairs/{pairId}`. `memberNames` is denormalised by the backend (ADDENDUM §M) so neither
/// side ever reads the other's user document — the rules would deny it anyway.
public struct Pair: Identifiable, Equatable, Sendable {
    public let id: String
    public let members: [String]
    public let memberNames: [String: String]
    public let status: String
    public let inviteCode: String
    public let createdBy: String
    public let createdAt: Int64

    public var isActive: Bool { status == "active" }
    public var isPending: Bool { status == "pending" }

    /// The paired person's uid, or nil while the pair is still pending.
    public func other(than uid: String) -> String? {
        members.first { $0 != uid }
    }

    public init?(id: String, data: [String: Any]) {
        guard let members = data["members"] as? [String],
              let status = str(data["status"]),
              let inviteCode = str(data["inviteCode"]),
              let createdBy = str(data["createdBy"]) else { return nil }
        self.id = id
        self.members = members
        self.memberNames = stringMap(data["memberNames"])
        self.status = status
        self.inviteCode = inviteCode
        self.createdBy = createdBy
        self.createdAt = long(data["createdAt"]) ?? 0
    }
}

/// `spots/{spotId}`.
public struct Spot: Identifiable, Equatable, Sendable {
    public let id: String
    public let pairId: String
    public let name: String
    public let lat: Double
    public let lng: Double
    public let radiusM: Double
    public let leadTimeMin: Int
    public let createdBy: String
    public let createdAt: Int64

    public var coordinate: LatLng { LatLng(lat: lat, lng: lng) }

    public init?(id: String, data: [String: Any]) {
        guard let pairId = str(data["pairId"]),
              let name = str(data["name"]),
              let lat = num(data["lat"]),
              let lng = num(data["lng"]) else { return nil }
        self.id = id
        self.pairId = pairId
        self.name = name
        self.lat = lat
        self.lng = lng
        self.radiusM = num(data["radiusM"]) ?? SpotLimits.defaultRadiusM
        self.leadTimeMin = int(data["leadTimeMin"]) ?? SpotLimits.defaultLeadTimeMin
        self.createdBy = str(data["createdBy"]) ?? ""
        self.createdAt = long(data["createdAt"]) ?? 0
    }
}

/// `trips/{tripId}`. Note the absent `lastPos` — see the header note.
public struct Trip: Identifiable, Equatable, Sendable {
    public let id: String
    public let pairId: String
    public let driverUid: String
    public let receiverUid: String
    public let spotId: String
    public let spot: TripSpot
    public let leadTimeMin: Int
    public let state: TripState
    public let createdAt: Int64
    public let startedAt: Int64?
    public let endedAt: Int64?
    public let eta: TripEta?
    public let bands: Bands?
    public let phaseHint: String
    public let routePolyline: String?
    public let receiverView: ReceiverView?
    public let alerts: TripAlerts
    public let fuzzy: Bool

    public init?(id: String, data: [String: Any]) {
        guard let pairId = str(data["pairId"]),
              let driverUid = str(data["driverUid"]),
              let receiverUid = str(data["receiverUid"]),
              let spot = TripSpot(dict(data["spot"])),
              let rawState = str(data["state"]) else { return nil }
        self.id = id
        self.pairId = pairId
        self.driverUid = driverUid
        self.receiverUid = receiverUid
        self.spotId = str(data["spotId"]) ?? ""
        self.spot = spot
        self.leadTimeMin = int(data["leadTimeMin"]) ?? SpotLimits.defaultLeadTimeMin
        // An unknown state means the server shipped something we do not know about; treat
        // it as `lost` (terminal, non-tracking) rather than dropping the whole document
        // and leaving the user staring at an empty screen.
        self.state = TripState(rawValue: rawState) ?? .lost
        self.createdAt = long(data["createdAt"]) ?? 0
        self.startedAt = long(data["startedAt"])
        self.endedAt = long(data["endedAt"])
        self.eta = TripEta(dict(data["eta"]))
        self.bands = Bands(dict(data["bands"]))
        self.phaseHint = str(data["phaseHint"]) ?? "far"
        self.routePolyline = str(data["routePolyline"])
        self.receiverView = ReceiverView(dict(data["receiverView"]))
        self.alerts = TripAlerts(dict(data["alerts"]))
        self.fuzzy = bool(data["fuzzy"]) ?? false
    }

    public func role(for uid: String) -> TripRole? {
        if uid == driverUid { return .driver }
        if uid == receiverUid { return .receiver }
        return nil
    }

    public func otherUid(for uid: String) -> String? {
        switch role(for: uid) {
        case .driver: return receiverUid
        case .receiver: return driverUid
        case .none: return nil
        }
    }

    /// `armed` or `driving` — the two states the active-trip query returns.
    public var isLive: Bool { state == .armed || state == .driving }

    /// Seconds until the receiver should stand up. Never negative.
    public var walkOutSeconds: Int {
        guard let eta else { return 0 }
        return max(0, eta.seconds - leadTimeMin * 60)
    }
}

/// `trips/{tripId}/replies/{autoId}`.
///
/// `kind` stays a `String` on the read side on purpose: the server may add a kind we do
/// not know, and a reply list must render it rather than crash. The WRITE side is the
/// closed `ReplyKind` enum in `Callables.swift` — exactly the contract's four.
public struct Reply: Identifiable, Equatable, Sendable {
    public let id: String
    public let fromUid: String
    public let kind: String
    public let text: String
    public let ts: Int64

    public init?(id: String, data: [String: Any]) {
        guard let fromUid = str(data["fromUid"]) else { return nil }
        self.id = id
        self.fromUid = fromUid
        self.kind = str(data["kind"]) ?? "custom"
        self.text = str(data["text"]) ?? ""
        self.ts = long(data["ts"]) ?? 0
    }
}
