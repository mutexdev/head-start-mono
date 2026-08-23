// ios/Headstart/Data/PositionUploader.swift
import Foundation

/// The only document shape clients are allowed to write
/// (CLIENT_CONTRACT.md §"The one thing clients write", CLIENT_CONTRACT_ADDENDUM.md §J:
/// exactly `lat, lng, accuracyM, speedMps, ts, expireAt` + optional `etaSec`).
/// `expireAt` is added by the sink, because it is a Firestore `Timestamp` and this type
/// stays Firebase-free.
public struct PositionUpload: Equatable, Sendable {
    public var lat: Double
    public var lng: Double
    public var accuracyM: Double
    public var speedMps: Double
    /// epoch milliseconds
    public var ts: Int64
    /// On-device ETA from `MKDirections.calculateETA` (decision D7). When present the
    /// server makes no routing call for this position. Omitted when MapKit failed.
    public var etaSec: Int?

    public init(lat: Double, lng: Double, accuracyM: Double, speedMps: Double, ts: Int64, etaSec: Int?) {
        self.lat = lat
        self.lng = lng
        self.accuracyM = accuracyM
        self.speedMps = speedMps
        self.ts = ts
        self.etaSec = etaSec
    }

    public init(fix: LocationFix, etaSec: Int?) {
        self.init(
            lat: fix.lat,
            lng: fix.lng,
            accuracyM: fix.accuracyM,
            speedMps: max(0, fix.speedMps),   // CoreLocation reports -1 for "unknown"
            ts: fix.tsMs,
            etaSec: etaSec
        )
    }
}

public protocol PositionSink: Sendable {
    /// Writes one position. Must throw on failure so the uploader can keep it buffered.
    func write(tripId: String, position: PositionUpload) async throws
}

/// Owns the offline buffer (decision D9). Fixes are appended in order, the oldest are
/// dropped once the cap is reached, and every drain replays oldest-first and stops at the
/// first failure so the remaining order is preserved. It never reorders, because the
/// server's `onPositionWrite` and the client's own `ts` guard both assume monotonic
/// timestamps.
///
/// It is an `actor` — the one exception to this batch's "plain value types" rule — because
/// the location callback and the retry timer both push into it concurrently.
public actor PositionUploader {

    private let tripId: String
    private let sink: PositionSink
    private let maxBuffer: Int
    private var buffer: [PositionUpload] = []

    /// How many fixes the cap has thrown away this trip — surfaced in the debug log only.
    public private(set) var dropped = 0

    public var pending: Int { buffer.count }

    public init(tripId: String, sink: PositionSink, maxBuffer: Int = 500) {
        self.tripId = tripId
        self.sink = sink
        self.maxBuffer = maxBuffer
    }

    /// Buffers the fix and immediately tries to drain. Returns how many were written.
    @discardableResult
    public func submit(_ position: PositionUpload) async -> Int {
        buffer.append(position)
        while buffer.count > maxBuffer {
            buffer.removeFirst()
            dropped += 1
        }
        return await drain()
    }

    /// Retries the backlog. Returns how many were written.
    @discardableResult
    public func flush() async -> Int {
        await drain()
    }

    private func drain() async -> Int {
        var sent = 0
        while let head = buffer.first {
            do {
                try await sink.write(tripId: tripId, position: head)
            } catch {
                break   // stay buffered, keep the order, try again on the next fix
            }
            // Actors are reentrant: another `submit` may have run during the await above
            // and the cap may have dropped this element. Only remove what we wrote.
            if let index = buffer.firstIndex(of: head) {
                buffer.remove(at: index)
            }
            sent += 1
        }
        return sent
    }
}
