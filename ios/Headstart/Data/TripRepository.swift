// ios/Headstart/Data/TripRepository.swift
//
// One listener for the pair's live trip, one for that trip's replies, and typed wrappers over
// the six trip callables.
//
// Composite index: `trips (pairId ASC, state ASC)` — declared by the backend in
// firestore.indexes.json. A `FAILED_PRECONDITION: The query requires an index` from here means
// the backend has not been deployed (or the emulator was started without the index file); it
// is not a bug in this file.
//
// A `PERMISSION_DENIED` carrying "Property driverUid is undefined on object. for 'list'" is
// also NOT a bug in this file. Firestore synthesises `resource` for a LIST from the query's
// own constraints, so only fields the client actually filtered on exist during rule
// evaluation. This query filters on `pairId` and `state` only — exactly as
// CLIENT_CONTRACT.md specifies — so a `trips` rule that dereferences
// `resource.data.driverUid` in its `allow read` rejects the whole query before it runs, and
// the active-trip stream silently never delivers: no trip screens, no Live Activity. Both
// client pipelines hit this on their end-to-end drives and `firestore.rules` now splits
// `get` from `list`, with the `list` half being `isMember(resource.data.pairId)`.
// Do NOT work around a recurrence here by adding `driverUid == uid` / `receiverUid == uid`
// filters: it does work (measured), but it needs two merged listeners and two composite
// indexes that firestore.indexes.json does not ship. Fix the rule.
//
// Three contract rules are enforced structurally here rather than by comment:
//
//  1. ADDENDUM §B — `sendReply` takes the closed `ReplyKind` enum, which has exactly the
//     contract's four cases. A fifth kind is not expressible. Being late is the separate
//     `setRunningLate` callable and reaches the receiver as a server push, never as a reply
//     document.
//  2. ADDENDUM §K — `extraMin` is clamped 1–60 before the call (again in `Callables`).
//  3. ADDENDUM §L — `setLowBattery` carries no tripId, so "once per trip" is a CLIENT-side
//     latch, and it lives here, keyed by tripId. It is set on the first report under 15 % and
//     never cleared for that trip. Android latches identically.

import Foundation
import FirebaseFirestore

@MainActor
public final class TripRepository: ObservableObject {

    /// The pair's one live trip (`armed` or `driving`), or nil.
    @Published public private(set) var activeTrip: Trip?

    /// Quick replies on the live trip, oldest first.
    @Published public private(set) var replies: [Reply] = []

    @Published public private(set) var hasLoaded = false

    private let db: Firestore
    private let callables: Callables
    private var tripTask: Task<Void, Never>?
    private var repliesTask: Task<Void, Never>?
    private var repliesTripId: String?

    /// ADDENDUM §L. Survives `stop()` on purpose: a trip id never comes back, so there is
    /// nothing to reset, and clearing it would let a second call slip out for the same trip
    /// after a sign-out/sign-in cycle mid-drive.
    private var lowBatteryReported: Set<String> = []

    public init(db: Firestore, callables: Callables) {
        self.db = db
        self.callables = callables
    }

    public func observe(pairId: String) {
        tripTask?.cancel()
        hasLoaded = false
        let stream = db.collection("trips")
            .whereField("pairId", isEqualTo: pairId)
            .whereField("state", in: [TripState.armed.rawValue, TripState.driving.rawValue])
            .modelsStream { Trip(id: $0, data: $1) }
        tripTask = Task { [weak self] in
            for await trips in stream {
                guard let self else { return }
                // `startTrip` rejects a second active trip, so there is at most one; prefer
                // `driving` if a stale `armed` document ever lingers alongside it.
                let next = trips.first { $0.state == .driving } ?? trips.first
                self.activeTrip = next
                self.hasLoaded = true
                self.syncReplies(for: next?.id)
            }
        }
    }

    public func stop() {
        tripTask?.cancel()
        tripTask = nil
        repliesTask?.cancel()
        repliesTask = nil
        repliesTripId = nil
        activeTrip = nil
        replies = []
        hasLoaded = false
    }

    private func syncReplies(for tripId: String?) {
        guard tripId != repliesTripId else { return }
        repliesTask?.cancel()
        repliesTask = nil
        repliesTripId = tripId
        replies = []
        guard let tripId else { return }
        let stream = db.collection("trips").document(tripId)
            .collection("replies")
            .order(by: "ts")
            .modelsStream { Reply(id: $0, data: $1) }
        repliesTask = Task { [weak self] in
            for await replies in stream {
                guard let self else { return }
                self.replies = replies
            }
        }
    }

    /// The most recent reply from the other person — the card on `DriverTrip`.
    public func latestReply(notFrom uid: String) -> Reply? {
        replies.last { $0.fromUid != uid }
    }

    // MARK: - Callables (CLIENT_CONTRACT.md)

    /// `etaSec` is the on-device MapKit ETA (decision D7, ADDENDUM §F): when it is present the
    /// server makes ZERO routing calls, so iOS always sends it when MapKit produced one.
    ///
    /// ADDENDUM §E — inspect `.existing` on the way out. True means a trip was already
    /// running for this pair and the client must ATTACH to it: do not restart tracking and do
    /// not replay first-start UI. Errors: `.notPaired`, `.spotNotFound`, `.badCoords`.
    public func startTrip(
        spotId: String,
        lat: Double,
        lng: Double,
        fuzzy: Bool,
        etaSec: Int?
    ) async throws -> StartTripResponse {
        try await callables.startTrip(
            spotId: spotId,
            lat: lat,
            lng: lng,
            fuzzy: fuzzy,
            etaSec: etaSec
        )
    }

    /// Receiver-initiated "ping me when they leave". `neededBy` is epoch milliseconds and is
    /// passed HERE — ADDENDUM §A, there is no separate callable for it in M1.
    /// Errors: `.tripActive`, `.notPaired`, `.spotNotFound`.
    @discardableResult
    public func armTrip(spotId: String, neededBy: Int64? = nil) async throws -> String {
        try await callables.armTrip(spotId: spotId, neededBy: neededBy).tripId
    }

    public func endTrip(tripId: String, reason: EndTripReason) async throws {
        try await callables.endTrip(tripId: tripId, reason: reason)
    }

    /// One of exactly four kinds (ADDENDUM §B). `text` is only meaningful for `.custom`, and
    /// empty custom text comes back as `.badReply` (ADDENDUM §O) — check it here so the
    /// editor can show its inline error without a round trip.
    public func sendReply(tripId: String, kind: ReplyKind, text: String? = nil) async throws {
        var body: String?
        if kind == .custom {
            let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw HeadstartError.badReply }
            body = String(trimmed.prefix(120))
        }
        try await callables.sendReply(tripId: tripId, kind: kind, text: body)
    }

    /// Driver only — the server rejects the receiver with `driver-only`. `extraMin` is clamped
    /// to 1–60 (ADDENDUM §K). The other person is told by the server's push, not by a reply
    /// document, so nothing is written to `replies` here.
    public func setRunningLate(tripId: String, extraMin: Int) async throws {
        try await callables.setRunningLate(
            tripId: tripId,
            extraMin: SpotLimits.clampExtraMin(extraMin)
        )
    }

    // MARK: - Low battery (ADDENDUM §L)

    /// The ONLY entry point for `setLowBattery` in the app. Call it from the tracking layer's
    /// one-shot "battery fell under 15 %" signal; it is safe to call on every fix.
    ///
    /// The latch is set BEFORE the call and never cleared, so a flapping battery reading or a
    /// retry loop can never produce a second call for the same trip. A failed call is
    /// therefore not retried within the trip — that is the deliberate reading of "once per
    /// trip", and it matches Android. The cost of missing it is that the server keeps the
    /// normal cadence; the cost of spamming it is a write per GPS fix.
    public func reportLowBattery(tripId: String) async {
        guard !lowBatteryReported.contains(tripId) else { return }
        lowBatteryReported.insert(tripId)
        do {
            try await callables.setLowBattery(true)
            NSLog("[HS][trip] setLowBattery(true) for \(tripId)")
        } catch {
            NSLog("[HS][trip] setLowBattery failed: \(error.asHeadstartError().code)")
        }
    }

    /// Test/inspection hook — has this trip already told the server?
    public func hasReportedLowBattery(tripId: String) -> Bool {
        lowBatteryReported.contains(tripId)
    }
}
