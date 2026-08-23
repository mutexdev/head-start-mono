// ios/Headstart/Data/PairRepository.swift
//
// Owns the single pair this user belongs to. Every mutation goes through a callable
// (`createPair`, `acceptPair`, `revokePair`) — the client never writes `pairs/{id}` — and the
// live read is a snapshot listener behind an `AsyncStream` (decision D8).
//
// Invite codes: the client only DISPLAYS a code the server minted and ACCEPTS one a person
// typed. It never generates one — CLIENT_CONTRACT.md line 12 fixes the alphabet server-side,
// and `PhoneNumber.sanitizeInviteCode` is the entry filter.

import Foundation
import FirebaseFirestore

@MainActor
public final class PairRepository: ObservableObject {

    /// The active pair if there is one; otherwise the PENDING invite this user created, so
    /// `PairInviteView` can keep showing the same code across app launches instead of
    /// minting a second one.
    @Published public private(set) var pair: Pair?

    /// False until the first snapshot lands. A screen that branches on `pair == nil` before
    /// this is true will flash the "not paired" state at every launch.
    @Published public private(set) var hasLoaded = false

    private let db: Firestore
    private let callables: Callables
    private var task: Task<Void, Never>?

    public init(db: Firestore, callables: Callables) {
        self.db = db
        self.callables = callables
    }

    /// ADDENDUM §M — a client finds its own pair with `members array-contains uid`. The
    /// `status` filter is applied HERE rather than in the query on purpose: as a single-field
    /// query this needs no composite index, and we also want the pending row (see `pair`).
    public func observe(uid: String) {
        task?.cancel()
        hasLoaded = false
        let stream = db.collection("pairs")
            .whereField("members", arrayContains: uid)
            .modelsStream { Pair(id: $0, data: $1) }
        task = Task { [weak self] in
            for await pairs in stream {
                guard let self else { return }
                self.pair = Self.pick(from: pairs, uid: uid)
                self.hasLoaded = true
            }
        }
    }

    /// Active always wins; a pending row only counts when this user is the one who created
    /// it, because a pending row created by someone else is just an invite they have not
    /// accepted and must not look like "you are paired".
    static func pick(from pairs: [Pair], uid: String) -> Pair? {
        pairs.first(where: \.isActive)
            ?? pairs.first { $0.isPending && $0.createdBy == uid }
    }

    public func stop() {
        task?.cancel()
        task = nil
        pair = nil
        hasLoaded = false
    }

    // MARK: - Callables

    /// Returns the six-character invite code to show on `PairInviteView`.
    public func create() async throws -> CreatePairResponse {
        try await callables.createPair()
    }

    /// `code` is sanitised here as well as in the field, so a caller that skipped the field
    /// (a deep link, `headstart://pair/K7M2QP`) cannot send something the server will bounce.
    /// Errors the UI must be ready for: `.badCode`, `.ownCode`.
    @discardableResult
    public func accept(code: String) async throws -> String {
        let clean = PhoneNumber.sanitizeInviteCode(code)
        guard clean.count == PhoneNumber.inviteCodeLength else { throw HeadstartError.badCode }
        return try await callables.acceptPair(code: clean).pairId
    }

    public func revoke() async throws {
        guard let pairId = pair?.id else { throw HeadstartError.notPaired }
        try await callables.revokePair(pairId: pairId)
    }

    // MARK: - Derived

    /// The other member's uid, or nil while the pair is pending.
    public func otherUid(selfUid: String) -> String? { pair?.other(than: selfUid) }

    /// Never nil — "Your partner" when the other side has no name yet.
    public func partnerName(selfUid: String) -> String {
        PartnerName.resolve(pair: pair, selfUid: selfUid)
    }
}
