// ios/Headstart/Push/DebugPushBridge.swift
//
// REQUIRED BY docs/CLIENT_CONTRACT_ADDENDUM.md, "Emulator contract":
//
//   "Both clients MUST ship a debug-only push bridge (#if DEBUG / debug source set): a
//    Firestore listener on `_debugPushes where toUid == me orderBy sentAt`, feeding each
//    new row into *the same* rendering path a real FCM/APNs message takes — same
//    `data.kind` switch, same channel, same interruption level. […] It must not exist in
//    a release build."
//
// WHY IT EXISTS. FCM cannot deliver from the emulator, so the server's `PushSender` writes
// the payload FCM WOULD have carried to `_debugPushes/{autoId}` instead. Without this
// bridge, the server's entire alert ladder — who gets told, when, and how urgently — is
// invisible on a simulator. The `xcrun simctl push` fixtures prove RENDERING of all
// thirteen kinds; this bridge proves the server's DECISIONS. Both are required, and they
// are not substitutes for one another.
//
// It funnels through `PushRouter.handle(userInfo:)` like every other delivery path, and it
// also posts a real local notification with the interruption level the server chose, so
// `leadTime` is visibly time-sensitive and the other twelve are visibly not.
//
// The whole file is inside `#if DEBUG`, and `ServiceLocator` only references it there.

#if DEBUG
import Foundation
import UserNotifications
import FirebaseFirestore

/// The `_debugPushes/{autoId}` shape is a contract with the backend
/// (functions/src/io/push.ts `DebugPushDoc`). Fields that go missing are tolerated —
/// a bridge that crashes on a partly-written row is worse than one that renders less.
@MainActor
public final class DebugPushBridge {

    private let db: Firestore
    private var task: Task<Void, Never>?
    private var seen: Set<String> = []
    /// Rows written before this launch are backlog, not news. Without this, relaunching
    /// replays every alert of every previous run in one burst.
    private var since: Int64 = 0

    public init(db: Firestore) {
        self.db = db
    }

    public var isRunning: Bool { task != nil }

    /// Starts listening for `uid`. Restarting for the same uid is a no-op-ish (the old
    /// listener is torn down first), so it is safe to call from an auth-state observer.
    public func start(uid: String) {
        stop()
        guard !uid.isEmpty else { return }
        since = Int64(Date().timeIntervalSince1970 * 1000)
        NSLog("[HS][debugpush] listening for uid=\(uid) since=\(since)")
        // Equality on one field only, deliberately: an `orderBy sentAt` alongside it would
        // demand a composite index that the backend does not ship for this debug-only
        // collection. Ordering is done locally instead, which is what the addendum's
        // "orderBy sentAt" is actually for.
        let query = db.collection("_debugPushes").whereField("toUid", isEqualTo: uid)
        task = Task { [weak self] in
            for await rows in query.modelsStream(DebugPush.init(id:data:)) {
                guard let self else { return }
                self.deliver(rows)
                if Task.isCancelled { return }
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        seen.removeAll()
    }

    private func deliver(_ rows: [DebugPush]) {
        for row in rows.sorted(by: { $0.sentAt < $1.sentAt }) {
            guard !seen.contains(row.id) else { continue }
            seen.insert(row.id)
            guard row.sentAt >= since else { continue }
            NSLog("[HS][debugpush] kind=\(row.kind) urgent=\(row.urgent) toUid=\(row.toUid)")
            // The same funnel every other delivery path uses.
            PushRouter.handle(userInfo: row.userInfo)
            present(row)
        }
    }

    /// Posts the notification the server would have sent, with the server's own
    /// interruption level, so the urgency mapping (ADDENDUM §C) is visible and not merely
    /// asserted in a unit test.
    private func present(_ row: DebugPush) {
        let content = UNMutableNotificationContent()
        content.title = row.title
        content.body = row.body
        content.sound = .default
        content.interruptionLevel = row.apnsInterruptionLevel == "time-sensitive" ? .timeSensitive : .active
        content.userInfo = row.userInfo
        let request = UNNotificationRequest(
            identifier: "headstart.debugpush.\(row.id)",
            content: content,
            trigger: nil
        )
        Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}

/// One `_debugPushes` row.
public struct DebugPush: Identifiable, Sendable {
    public let id: String
    public let toUid: String
    public let kind: String
    public let title: String
    public let body: String
    public let urgent: Bool
    public let apnsInterruptionLevel: String
    public let data: [String: String]
    public let sentAt: Int64

    public init?(id: String, data raw: [String: Any]) {
        guard let toUid = raw["toUid"] as? String else { return nil }
        self.id = id
        self.toUid = toUid
        let payload = (raw["data"] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
        self.data = payload
        self.kind = (raw["kind"] as? String) ?? payload["kind"] ?? ""
        self.title = (raw["title"] as? String) ?? ""
        self.body = (raw["body"] as? String) ?? ""
        self.urgent = (raw["urgent"] as? Bool) ?? false
        self.apnsInterruptionLevel = (raw["apnsInterruptionLevel"] as? String)
            ?? (self.urgent ? "time-sensitive" : "active")
        self.sentAt = ((raw["sentAt"] as? NSNumber)?.int64Value) ?? 0
    }

    /// Rebuilt into exactly the dictionary an APNs delivery would have produced, so
    /// `PushPayload` cannot tell the two apart.
    public var userInfo: [AnyHashable: Any] {
        [
            "aps": [
                "alert": ["title": title, "body": body],
                "interruption-level": apnsInterruptionLevel,
            ],
            "data": data,
        ]
    }
}
#endif
