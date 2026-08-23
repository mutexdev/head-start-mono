// ios/Headstart/Data/FirestorePositionSink.swift
//
// THE ONE AND ONLY THING THIS CLIENT WRITES TO FIRESTORE.
//
// CLIENT_CONTRACT.md "The one thing clients write" and CLIENT_CONTRACT_ADDENDUM.md §J fix
// the document at exactly seven keys:
//
//     lat, lng, accuracyM, speedMps, ts, expireAt      (always)
//     etaSec                                            (only when present)
//
// The security rules reject any extra field, and any writer whose uid is not
// `trip.driverUid`, so a mistake here surfaces immediately as PERMISSION_DENIED rather
// than as silently corrupt data. Specifically, and deliberately:
//   - `expireAt` is a REAL `Timestamp(date: now + 30 days)`, not a serverTimestamp
//     sentinel. A sentinel would arrive as a pending value the TTL policy cannot use.
//   - `etaSec` is OMITTED when nil. Writing NSNull would be an eighth key and fail rules.
//   - no client-generated id, no createdAt, no uid, no anything else.
//
// The set of keys is asserted by a unit test over `documentFields(for:)`, which is the
// same dictionary the write uses, so the assertion cannot drift from the write.

import Foundation
import FirebaseFirestore

public struct FirestorePositionSink: PositionSink {

    /// `Firestore` is not `Sendable` in the 12.18 SDK, and `PositionSink` is `Sendable`
    /// because the tracking layer hands it across isolation. Storing the handle directly
    /// would need `@preconcurrency import`, which downgrades every real Sendable
    /// diagnostic in this file to a warning. Storing a factory instead keeps the import
    /// clean: the handle is created and used entirely inside one call, never stored, never
    /// shared. `Firestore.firestore()` returns the same cached instance every time, so
    /// this costs nothing.
    private let database: @Sendable () -> Firestore

    /// Positions carry a 30-day TTL (spec §2, `expireAt` field override).
    public static let ttl: TimeInterval = 30 * 24 * 60 * 60

    /// The exact key set the rules allow. Ordered as the contract lists them.
    public static let requiredKeys = ["lat", "lng", "accuracyM", "speedMps", "ts", "expireAt"]
    public static let optionalKeys = ["etaSec"]

    public init(database: @escaping @Sendable () -> Firestore = { Firestore.firestore() }) {
        self.database = database
    }

    /// Built separately from the write so a test can assert the key set without Firestore.
    /// `now` is injectable for the same reason.
    public static func documentFields(for position: PositionUpload, now: Date = Date()) -> [String: Any] {
        var data: [String: Any] = [
            "lat": position.lat,
            "lng": position.lng,
            "accuracyM": position.accuracyM,
            "speedMps": position.speedMps,
            // epoch milliseconds, as a 64-bit integer — the contract's `ts: Long`.
            "ts": NSNumber(value: position.ts),
            "expireAt": Timestamp(date: now.addingTimeInterval(ttl)),
        ]
        if let etaSec = position.etaSec {
            data["etaSec"] = NSNumber(value: etaSec)
        }
        return data
    }

    public func write(tripId: String, position: PositionUpload) async throws {
        do {
            _ = try await database().collection("trips")
                .document(tripId)
                .collection("positions")
                .addDocument(data: Self.documentFields(for: position))
        } catch {
            throw error.asHeadstartError()
        }
    }
}
