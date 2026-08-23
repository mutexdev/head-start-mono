// ios/Headstart/Push/PushService.swift
//
// Owns the notification permission, the FCM token round-trip, and the local test alert
// behind Settings → "Send me a test alert".
//
// WHAT IS AND IS NOT PROVABLE HERE. The Simulator cannot receive FCM, and no APNs `.p8`
// key exists for this project, so `Messaging.token()` will fail or hang forever on this
// machine. That is expected and must never block anything: `registerCurrentToken()` is
// time-boxed, swallows the failure, logs
//
//     [HS][push] fcm-token-unavailable (simulator)
//
// and returns. Token registration is proven on a real device only; the RENDERING and
// ROUTING of all thirteen kinds is proven here with `xcrun simctl push` fixtures, and the
// server's alert DECISIONS are proven by the `_debugPushes` bridge. What is left over is
// real-device-only and lives in docs/testing/real-drive-checklist.md.

import Foundation
import UserNotifications
import UIKit
import FirebaseMessaging

@MainActor
public final class PushService: ObservableObject {

    @Published public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published public private(set) var fcmToken: String?

    private let callables: Callables
    /// Set from `ProfileView`'s name, sent alongside the token so the server can address
    /// the other member by name in push copy without reading a user document.
    private var displayName: String?

    /// FCM registration can never complete without APNs. 5 s is generous for a real device
    /// and instant-ish for the simulator's failure path. `nonisolated` because the timeout
    /// task below runs outside the main actor.
    private nonisolated static let tokenTimeout: Duration = .seconds(5)

    public init(callables: Callables) {
        self.callables = callables
    }

    public func setDisplayName(_ name: String?) {
        displayName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Permission

    /// Asks once. iOS only shows the system sheet the first time; afterwards this just
    /// reports what the user already decided.
    @discardableResult
    public func requestAuthorization() async -> UNAuthorizationStatus {
        let centre = UNUserNotificationCenter.current()
        _ = try? await centre.requestAuthorization(options: [.alert, .sound, .badge])
        let status = await centre.notificationSettings().authorizationStatus
        authorizationStatus = status
        if status == .authorized || status == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
        NSLog("[HS][push] authorization=\(Self.describe(status))")
        return status
    }

    public func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
    }

    // MARK: - Token

    /// Called after sign-in and on every refresh (CLIENT_CONTRACT.md, `registerPushToken`).
    public func register(token: String) async {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        fcmToken = token
        do {
            try await callables.registerPushToken(
                token: token,
                platform: .ios,
                displayName: displayName
            )
            NSLog("[HS][push] registered token …\(String(token.suffix(6)))")
        } catch {
            // A failed registration must not block sign-in or the home screen; the next
            // refresh (or the next launch) retries.
            NSLog("[HS][push] registerPushToken failed: \((error as? HeadstartError)?.code ?? "unknown")")
        }
    }

    /// Called from `AppDelegate`'s `MessagingDelegate`. Caches the token UNCONDITIONALLY
    /// and only sends it to the server when somebody is signed in — `registerPushToken` is
    /// an authenticated callable, and FCM usually hands the token over before sign-in.
    /// Without the cache the first-run ordering loses the token entirely.
    public func handleTokenRefresh(_ token: String, signedIn: Bool) async {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        fcmToken = token
        guard signedIn else {
            NSLog("[HS][push] fcm token cached, waiting for sign-in")
            return
        }
        await register(token: token)
    }

    /// Called right after sign-in. Sends the cached token if FCM already produced one,
    /// otherwise asks FCM to start registering — the token then arrives through
    /// `MessagingDelegate` and lands back in `handleTokenRefresh`.
    ///
    /// `Messaging.fcmToken` and `Messaging.token()` are both deprecated in 12.18.0 in
    /// favour of exactly this delegate-driven flow, so this is not a workaround.
    public func registerCurrentToken() async {
        if let token = fcmToken, !token.isEmpty {
            await register(token: token)
            return
        }
        if let failure = await Self.kickRegistration() {
            // The expected outcome on a Simulator: no APNs token, so no FCM token.
            NSLog("[HS][push] fcm-token-unavailable (simulator): \(failure)")
        } else {
            NSLog("[HS][push] fcm registration requested — token arrives via MessagingDelegate")
        }
    }

    /// Time-boxed. Without an APNs token FCM registration cannot complete, and no caller
    /// may be left awaiting forever because this machine has no APNs key.
    /// Returns nil on success, a description on failure.
    private static func kickRegistration() async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                do {
                    try await Messaging.messaging().register()
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
            group.addTask {
                try? await Task.sleep(for: tokenTimeout)
                return "timed out"
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Local test alert (Settings)

    /// Settings → "Send me a test alert". M1 has no server-side test-push callable, so
    /// this is a LOCAL notification five seconds out. It proves the permission, the sound
    /// and the on-device delivery path — it does NOT prove APNs or FCM. The honest
    /// end-to-end check is the real drive on two phones.
    public func sendTestAlert() async throws {
        let content = UNMutableNotificationContent()
        content.title = "Start walking now"
        content.body = "This is what the walk-out alert looks like."
        content.sound = .default
        // The one urgent kind in the product (ADDENDUM §C), so the test alert shows the
        // user exactly the treatment the real one gets.
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["data": ["kind": PushKind.leadTime.rawValue]]
        let request = UNNotificationRequest(
            identifier: "headstart.test.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        try await UNUserNotificationCenter.current().add(request)
        NSLog("[HS][push] local test alert scheduled")
    }

    // MARK: -

    private static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .denied: "denied"
        case .authorized: "authorized"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        @unknown default: "unknown"
        }
    }
}
