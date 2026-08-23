// ios/Headstart/Data/SpotRepository.swift
//
// `spots where pairId == …` is a single-field query, so no composite index is needed.
//
// ADDENDUM §K — this repository is where the client-side clamps live. The server clamps
// `leadTimeMin` to 1–30 and `radiusM` to 50–500 too, but an out-of-range value that reaches
// the wire comes back as a callable error a person cannot interpret. Clamping here AND
// constraining the editor's controls means an illegal value is never expressible in the
// first place. `Callables.upsertSpot` clamps a third time at the wire boundary; the clamps
// are idempotent, so the belt and the braces cost nothing.

import Foundation
import FirebaseFirestore

@MainActor
public final class SpotRepository: ObservableObject {

    @Published public private(set) var spots: [Spot] = []
    @Published public private(set) var hasLoaded = false

    private let db: Firestore
    private let callables: Callables
    private var task: Task<Void, Never>?

    public init(db: Firestore, callables: Callables) {
        self.db = db
        self.callables = callables
    }

    public func observe(pairId: String) {
        task?.cancel()
        hasLoaded = false
        let stream = db.collection("spots")
            .whereField("pairId", isEqualTo: pairId)
            .modelsStream { Spot(id: $0, data: $1) }
        task = Task { [weak self] in
            for await spots in stream {
                guard let self else { return }
                // Oldest first, so the list does not reshuffle under a thumb when the
                // server backfills a field on an existing spot.
                self.spots = spots.sorted { $0.createdAt < $1.createdAt }
                self.hasLoaded = true
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        spots = []
        hasLoaded = false
    }

    public func spot(id: String) -> Spot? { spots.first { $0.id == id } }

    // MARK: - Callables

    /// Errors: `.badName` (empty or >40 characters), `.badCoords` (non-finite), `.notPaired`.
    /// `leadTimeMin` and `radiusM` are clamped to the contract's ranges before the call.
    @discardableResult
    public func upsert(
        pairId: String,
        name: String,
        lat: Double,
        lng: Double,
        leadTimeMin: Int,
        radiusM: Double,
        spotId: String? = nil
    ) async throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HeadstartError.badName }
        guard lat.isFinite, lng.isFinite,
              abs(lat) <= 90, abs(lng) <= 180 else { throw HeadstartError.badCoords }
        // ADDENDUM §K: leadTimeMin 1–30, radiusM 50–500.
        let clampedLeadTimeMin = SpotLimits.clampLeadTimeMin(leadTimeMin)
        let clampedRadiusM = SpotLimits.clampRadiusM(radiusM)
        let response = try await callables.upsertSpot(
            pairId: pairId,
            name: String(trimmed.prefix(40)),
            lat: lat,
            lng: lng,
            leadTimeMin: clampedLeadTimeMin,
            radiusM: clampedRadiusM,
            spotId: spotId
        )
        return response.spotId
    }

    public func delete(spotId: String) async throws {
        try await callables.deleteSpot(spotId: spotId)
    }
}
