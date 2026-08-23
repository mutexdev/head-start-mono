// ios/Headstart/AppDelegate.swift
//
// Firebase must be configured before any Firebase API is touched, and the
// UIApplicationDelegate is the only place guaranteed to run before SwiftUI's first view
// body. It therefore also owns every APNs callback, because THREE consumers need the
// device token and each of them fails differently and silently without it:
//
//   Firebase Auth — phone sign-in verifies the app with a silent push. No token means a
//                   reCAPTCHA web view on every attempt (or, on a simulator, nothing).
//   FCM           — will not mint a registration token at all until `apnsToken` is set.
//   Us            — the alert ladder.
//
// `FirebaseAppDelegateProxyEnabled` is `false` in Info.plist (set in ios1), so Firebase's
// method swizzling is OFF and every forward below is explicit. That is deliberate: it is
// what makes the `[HS][push]` log line a trustworthy assertion rather than a hope.

import UIKit
import UserNotifications
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseMessaging

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        Self.wireBackend()
        // Force the locator into existence NOW, after the emulator wiring and before the
        // first push can arrive. It is what connects `PushRouter.onEndLiveActivity` to
        // `LiveActivityController`, and a push that lands before anything has touched
        // `ServiceLocator.shared` would otherwise route with that hook still nil.
        _ = ServiceLocator.shared
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        // Registered here rather than only after the permission prompt: the Auth
        // app-verification token is needed before the user has agreed to anything, and a
        // silent push needs no user permission. On the Simulator this fails and lands in
        // `didFailToRegisterForRemoteNotifications`, which is expected and harmless.
        application.registerForRemoteNotifications()
        return true
    }

    /// Point Auth / Firestore / Functions at the emulator suite when
    /// `BackendEnvironment` says so. This MUST run immediately after
    /// `FirebaseApp.configure()` and before any other Firebase call:
    /// `Firestore.settings` may only be assigned before the instance is first
    /// used, otherwise the SDK throws.
    private static func wireBackend() {
        if let host = BackendEnvironment.emulatorHost {
            Auth.auth().useEmulator(withHost: host, port: BackendEnvironment.authPort)
            let s = Firestore.firestore().settings
            s.host = "\(host):\(BackendEnvironment.firestorePort)"
            s.isSSLEnabled = false
            s.cacheSettings = MemoryCacheSettings()
            Firestore.firestore().settings = s
            Functions.functions().useEmulator(withHost: host, port: BackendEnvironment.functionsPort)
            NSLog("[HS] backend=emulator host=\(host)")
        } else {
            NSLog("[HS] backend=cloud")
        }
    }

    // MARK: - APNs

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Both consumers need it, and FCM will not mint a token without the first line.
        Messaging.messaging().apnsToken = deviceToken
        // `.unknown` lets the SDK pick sandbox vs production from the build; hard-coding
        // either one is the classic "works in debug, silent in TestFlight" bug.
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
        NSLog("[HS][push] apns token registered (\(deviceToken.count) bytes)")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Always the case on a Simulator with no paid team. Never fatal.
        NSLog("[HS][push] apns registration failed: \(error.localizedDescription)")
    }

    /// Silent / background pushes, and the path `xcrun simctl push` takes for a payload
    /// carrying `content-available: 1`.
    ///
    /// Firebase Auth's app-verification push arrives here too and must be handed straight
    /// back to it — swallowing it is what makes phone sign-in fall back to reCAPTCHA.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        let handled = PushRouter.handle(userInfo: userInfo)
        completionHandler(handled ? .newData : .noData)
    }

    /// The reCAPTCHA fallback returns through the REVERSED_CLIENT_ID URL scheme.
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        Auth.auth().canHandle(url)
    }
}

// MARK: - FCM registration token

extension AppDelegate: MessagingDelegate {
    /// `nonisolated` because `MessagingDelegate` carries no actor isolation; the hop to
    /// the main actor is explicit and carries only the `Sendable` token string.
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else {
            NSLog("[HS][push] fcm-token-unavailable (simulator)")
            return
        }
        Task { @MainActor in
            // The token is cached unconditionally and only SENT once somebody is signed in
            // — `registerPushToken` is an authenticated callable, and FCM normally hands
            // the token over before sign-in. `ios7` calls `push.registerCurrentToken()`
            // straight after sign-in, which then finds the cached value.
            await ServiceLocator.shared.push.handleTokenRefresh(
                fcmToken,
                signedIn: Auth.auth().currentUser != nil
            )
        }
    }
}

// MARK: - Notification presentation and taps
//
// Both callbacks funnel into `PushRouter.handle(userInfo:)` — the SAME entry point the
// remote-notification path above uses. One funnel, one log line, one assertion.

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// Show alerts even while the app is in the foreground: a driver staring at the trip
    /// screen still needs to see "Traffic — now 14 min".
    /// `nonisolated`: `UNUserNotificationCenterDelegate` carries no actor isolation, and
    /// `UNNotification` is not `Sendable`, so a main-actor-isolated witness cannot receive
    /// it under Swift 6. Parsing happens here, off the main actor, and only the `Sendable`
    /// `PushPayload` crosses — which is exactly why `PushRouter.handle(userInfo:)` is a
    /// nonisolated static function.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        PushRouter.handle(userInfo: notification.request.content.userInfo)
        return [.banner, .list, .sound]
    }

    /// The user tapped the notification.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        PushRouter.handle(userInfo: response.notification.request.content.userInfo)
    }
}
