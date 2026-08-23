// ios/Headstart/UI/Permissions.swift
//
// The two permission prompts, in the ONE order the product can survive, and in the one
// place they are ever asked for.
//
// WHY NOTIFICATIONS FIRST. If the user denies location we can still deliver the walk-out
// alert to them as a RECEIVER — the whole receiver half of the product keeps working. If
// they deny notifications the product does nothing at all: every alert the server decides
// to send lands nowhere. So the prompt that matters most is asked while the primer that
// explains it is still on screen (`design/Profile.dc.html`), and location follows.
//
// WHY WHEN-IN-USE ONLY (decision D6). `LocationTracker` deliberately has no
// Always-authorization entry point. The contract's tracking model is "the driver taps
// I'm coming and watches the trip", and Always would buy nothing except a scarier prompt
// and an App Store review conversation. `UIBackgroundModes: [location]` plus
// `allowsBackgroundLocationUpdates` is what keeps uploads alive with the app backgrounded,
// and that needs no Always grant.
//
// NEITHER IS RE-PROMPTED. iOS only shows each system sheet once; afterwards a request is
// a no-op that reports the decision the user already made. `SettingsView` links out to the
// system settings, which is the only real remedy.

import Foundation
import CoreLocation
import UserNotifications

/// Asked exactly once, from `ProfileView`'s "Allow and continue" (`AppViewModel.completeProfile`).
/// Nothing else in the app may call `requestAuthorization` or `requestWhenInUseAuthorization`.
public enum Permissions {

    /// The result of the onboarding prompt pair, for logging and for `SettingsView`.
    public struct Outcome: Equatable, Sendable {
        public let notifications: UNAuthorizationStatus
        public let location: CLAuthorizationStatus

        public var notificationsGranted: Bool {
            notifications == .authorized || notifications == .provisional
        }
        public var locationGranted: Bool {
            location == .authorizedWhenInUse || location == .authorizedAlways
        }
    }

    /// Notifications, then location. Sequential on purpose: two system sheets racing each
    /// other is a coin flip over which one the user actually reads, and iOS will not show
    /// the second until the first is dismissed anyway.
    @MainActor
    @discardableResult
    public static func requestOnboarding(
        push: PushService,
        tracker: LocationTracker
    ) async -> Outcome {
        let notifications = await push.requestAuthorization()
        let location = await tracker.requestWhenInUseAuthorization()
        let outcome = Outcome(notifications: notifications, location: location)
        NSLog(
            "[HS][perm] notifications=%@ location=%@",
            outcome.notificationsGranted ? "granted" : "denied",
            outcome.locationGranted ? "granted" : "denied"
        )
        return outcome
    }
}
