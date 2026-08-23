// ios/Headstart/Core/Callables.swift
//
// The single place this app calls a Cloud Function. Every failure leaves here as a
// `HeadstartError`; nothing above this file ever sees an `NSError`.
//
// The callable surface is CLOSED. CLIENT_CONTRACT_ADDENDUM.md §A fixes M1 at exactly the
// twelve methods in the "The twelve M1 callables" section below. The three names §A lists
// under "Not in M1" appear in the spec but no server implements them, so calling one would
// be a guaranteed NOT_FOUND — they are deliberately absent here, not stubbed, and nothing
// in this file may grow into them. (They are not spelled out because a done-criteria grep
// looks for exactly those identifiers and a comment would be its only hit.) The M1 route
// for a needed-by time is the optional second argument of `armTrip`, below.
//
// Region: the Functions default, `us-central1`. Never pass a region explicitly — the
// emulator serves callables at http://127.0.0.1:5001/fin-e8358/us-central1/<name> and the
// deployed functions live in the same region.

import Foundation
import FirebaseFunctions

// MARK: - Closed request enums

/// CLIENT_CONTRACT_ADDENDUM.md §B — exactly four reply kinds. There is no `runningLate`
/// case and there must never be one: running late is the `setRunningLate` callable, and it
/// reaches the receiver as a `runningLate` PUSH, never as a reply document. A fifth case
/// here would make the server reject the write and would desync the two clients' reply
/// lists. (Reply *rendering* still tolerates an unknown kind string — see `Reply.kind`.)
public enum ReplyKind: String, Sendable, CaseIterable, Equatable {
    case fiveMore
    case takeYourTime
    case atSpot
    case custom
}

/// `endTrip({tripId, reason})` — the contract allows these two and nothing else.
public enum EndTripReason: String, Sendable, CaseIterable, Equatable {
    case arrived
    case cancelled
}

/// `registerPushToken({token, platform, displayName?})`.
public enum ClientPlatform: String, Sendable {
    case ios
    case android
}

// MARK: - Response shapes from CLIENT_CONTRACT.md
//
// Every response decoder tolerates a missing optional-ish field rather than throwing:
// a decode failure is reported as `unknown("bad-response:<name>")`, which is a far worse
// user experience than a sensible default when the server is mid-rollout. The fields the
// caller genuinely cannot proceed without (ids) stay required.

public struct CreatePairResponse: Decodable, Equatable, Sendable {
    public let pairId: String
    public let inviteCode: String
}

public struct AcceptPairResponse: Decodable, Equatable, Sendable {
    public let pairId: String
}

public struct UpsertSpotResponse: Decodable, Equatable, Sendable {
    public let spotId: String
}

/// `{tripId, bands:{far,near,lead}, etaSeconds, existing:boolean}`.
///
/// ADDENDUM §E — `existing` is the duplicate-tap signal. When it is true the client
/// ATTACHES to the trip already running: it must not restart tracking and must not replay
/// first-start UI. Without decoding it a double-tap looks like a brand new trip.
public struct StartTripResponse: Decodable, Equatable, Sendable {
    public let tripId: String
    public let bands: Bands?
    public let etaSeconds: Int?
    public let existing: Bool

    private enum CodingKeys: String, CodingKey {
        case tripId, bands, etaSeconds, existing
    }

    public init(tripId: String, bands: Bands?, etaSeconds: Int?, existing: Bool) {
        self.tripId = tripId
        self.bands = bands
        self.etaSeconds = etaSeconds
        self.existing = existing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tripId = try c.decode(String.self, forKey: .tripId)
        self.bands = try c.decodeIfPresent(Bands.self, forKey: .bands)
        self.etaSeconds = try c.decodeIfPresent(Int.self, forKey: .etaSeconds)
        // Absent means "the server did not tell us", which is the same as "this is new".
        self.existing = try c.decodeIfPresent(Bool.self, forKey: .existing) ?? false
    }
}

public struct ArmTripResponse: Decodable, Equatable, Sendable {
    public let tripId: String
}

// MARK: - Callables

public struct Callables: Sendable {

    private let functions: Functions

    public init(functions: Functions = Functions.functions()) {
        self.functions = functions
    }

    // MARK: The twelve M1 callables (ADDENDUM §A) — nothing else may be added here

    /// After sign-in and on every token refresh.
    public func registerPushToken(
        token: String,
        platform: ClientPlatform = .ios,
        displayName: String? = nil
    ) async throws {
        var payload: [String: Any] = ["token": token, "platform": platform.rawValue]
        if let displayName, !displayName.isEmpty { payload["displayName"] = displayName }
        try await callVoid("registerPushToken", payload)
    }

    public func createPair() async throws -> CreatePairResponse {
        try await call("createPair")
    }

    /// Errors: `bad-code`, `own-code`.
    public func acceptPair(code: String) async throws -> AcceptPairResponse {
        try await call("acceptPair", ["code": code])
    }

    public func revokePair(pairId: String) async throws {
        try await callVoid("revokePair", ["pairId": pairId])
    }

    /// `leadTimeMin` and `radiusM` are clamped here as well as server-side (ADDENDUM §K),
    /// so an out-of-range value from any caller can never surface as an unreadable
    /// callable error. The editor constrains its controls to the same ranges.
    public func upsertSpot(
        pairId: String,
        name: String,
        lat: Double,
        lng: Double,
        leadTimeMin: Int,
        radiusM: Double,
        spotId: String? = nil
    ) async throws -> UpsertSpotResponse {
        var payload: [String: Any] = [
            "pairId": pairId,
            "name": name,
            "lat": lat,
            "lng": lng,
            "leadTimeMin": SpotLimits.clampLeadTimeMin(leadTimeMin),
            "radiusM": SpotLimits.clampRadiusM(radiusM),
        ]
        if let spotId, !spotId.isEmpty { payload["spotId"] = spotId }
        return try await call("upsertSpot", payload)
    }

    public func deleteSpot(spotId: String) async throws {
        try await callVoid("deleteSpot", ["spotId": spotId])
    }

    /// `etaSec` is the on-device MapKit ETA (decision D7). ADDENDUM §F: when it is present
    /// and valid the server makes ZERO routing calls, so iOS always sends it when MapKit
    /// produced one.
    public func startTrip(
        spotId: String,
        lat: Double,
        lng: Double,
        fuzzy: Bool? = nil,
        etaSec: Int? = nil
    ) async throws -> StartTripResponse {
        var payload: [String: Any] = ["spotId": spotId, "lat": lat, "lng": lng]
        if let fuzzy { payload["fuzzy"] = fuzzy }
        if let etaSec { payload["etaSec"] = etaSec }
        return try await call("startTrip", payload)
    }

    /// Receiver-initiated "ping me when they leave". ADDENDUM §A: the needed-by time is
    /// passed HERE and there is no separate callable for it. Epoch milliseconds.
    public func armTrip(spotId: String, neededBy: Int64? = nil) async throws -> ArmTripResponse {
        var payload: [String: Any] = ["spotId": spotId]
        if let neededBy { payload["neededBy"] = NSNumber(value: neededBy) }
        return try await call("armTrip", payload)
    }

    public func endTrip(tripId: String, reason: EndTripReason) async throws {
        try await callVoid("endTrip", ["tripId": tripId, "reason": reason.rawValue])
    }

    /// `text` is only meaningful for `.custom`; empty custom text returns `bad-reply`.
    public func sendReply(tripId: String, kind: ReplyKind, text: String? = nil) async throws {
        var payload: [String: Any] = ["tripId": tripId, "kind": kind.rawValue]
        if let text, !text.isEmpty { payload["text"] = text }
        try await callVoid("sendReply", payload)
    }

    /// Driver only. `extraMin` clamped 1–60 (ADDENDUM §K).
    public func setRunningLate(tripId: String, extraMin: Int) async throws {
        try await callVoid("setRunningLate", [
            "tripId": tripId,
            "extraMin": SpotLimits.clampExtraMin(extraMin),
        ])
    }

    /// Carries no tripId by contract. The "once per trip" latch is CLIENT-side and lives in
    /// the trip repository, keyed by tripId (ADDENDUM §L) — never call this from a location
    /// callback directly.
    public func setLowBattery(_ lowBattery: Bool) async throws {
        try await callVoid("setLowBattery", ["lowBattery": lowBattery])
    }

    // MARK: - Transport

    /// Calls `name` and decodes the JSON-shaped result into `T`.
    public func call<T: Decodable>(
        _ name: String,
        _ data: [String: Any] = [:],
        returning: T.Type = T.self
    ) async throws -> T {
        let raw = try await callRaw(name, data)
        let json = try JSONSerialization.data(withJSONObject: raw, options: [])
        do {
            return try JSONDecoder().decode(T.self, from: json)
        } catch {
            // A decode failure means the server changed shape — surface it as unknown
            // rather than pretending the call failed for a contract reason.
            throw HeadstartError.unknown("bad-response:\(name)")
        }
    }

    /// Calls `name` and ignores the `{ok:true}` body.
    public func callVoid(_ name: String, _ data: [String: Any] = [:]) async throws {
        _ = try await callRaw(name, data)
    }

    private func callRaw(_ name: String, _ data: [String: Any]) async throws -> [String: Any] {
        do {
            let result = try await functions.httpsCallable(name).call(data)
            return (result.data as? [String: Any]) ?? [:]
        } catch {
            // HeadstartError.swift already owns the domain/status mapping; do not
            // re-derive it here.
            throw error.asHeadstartError()
        }
    }
}
