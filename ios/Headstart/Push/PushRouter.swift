// ios/Headstart/Push/PushRouter.swift
//
// The in-process bus between "a notification arrived, from wherever" and "the view tree
// does something". THE FUNNEL IS `PushRouter.handle(userInfo:)` AND THERE IS NO OTHER —
// the remote-notification path, both UNUserNotificationCenter delegate callbacks and the
// `#if DEBUG` `_debugPushes` bridge all call exactly that one static function.
//
// Why it matters that they funnel: on this machine there is no APNs key, no paid team and
// no phone, so the only way to prove a push was routed is to deliver a fixture with
//
//     xcrun simctl push <udid> com.mutexdev.headstart ios/fixtures/push/leadTime.apns
//
// and read the log stream. One entry point, one `[HS][push] kind=… tripId=…` line, and
// the assertion is trustworthy. Two entry points and it is not.
//
// The decision itself — kind ⇒ where the app should go — is the PURE static
// `destination(for:)`, so it is unit-tested without UIKit, a simulator or a delegate.

import Foundation
import SwiftUI

/// Where an arriving alert wants the app to be. `ios7`'s `AppViewModel` consumes this;
/// nothing in this batch navigates on its own.
public enum PushDestination: Equatable, Sendable {
    /// Unknown kind, or a kind with no screen of its own. Render the banner, do nothing else.
    case ignore
    /// The live trip screen — `DriverTripView` or `ReceiverTripView`, whichever role the
    /// trip document says this user has.
    case trip(tripId: String?)
    /// The trip is over. Home.
    case home
    /// `design/DriverNudge.dc.html` over the driver's trip screen.
    case driverNudge(tripId: String?)
}

@MainActor
public final class PushRouter: ObservableObject {

    public static let shared = PushRouter()

    /// The most recent payload, for anything that wants to react exactly once.
    @Published public private(set) var lastPayload: PushPayload?
    /// Where the last payload wants the app to go. `ios7` observes this.
    @Published public private(set) var destination: PushDestination = .ignore
    /// `didYouLeave` raises the driver sheet. The view clears it via `dismissDriverNudge()`.
    @Published public var showDriverNudge = false

    /// Wired by `ServiceLocator` to `LiveActivityController.end()`. A terminal push can
    /// arrive while the trip listener is detached (app backgrounded), and the Lock Screen
    /// must not keep counting down to a pickup that already happened.
    public var onEndLiveActivity: (() -> Void)?

    public init() {}

    // MARK: - The single entry point
    //
    // `nonisolated` on purpose: `application(_:didReceiveRemoteNotification:…)` is
    // main-actor isolated but the two `UNUserNotificationCenterDelegate` async methods are
    // not, and `[AnyHashable: Any]` is not `Sendable` so it cannot be carried across an
    // isolation boundary. Parsing here — into the `Sendable` `PushPayload` — is what lets
    // every path share one funnel under Swift 6 strict concurrency.

    /// Parse, log, route. Safe to call from any isolation domain, any thread.
    /// Returns true when the dictionary was one of ours.
    @discardableResult
    public nonisolated static func handle(userInfo: [AnyHashable: Any]) -> Bool {
        guard let payload = PushPayload(userInfo: userInfo) else {
            NSLog("[HS][push] ignored — no data.kind")
            return false
        }
        // THE assertion line for the headless drive. Do not reword without updating
        // ios/fixtures/push/README.md and whatever is grepping the log stream.
        NSLog("[HS][push] kind=\(payload.kind.rawValue) tripId=\(payload.tripId ?? "-")")
        Task { @MainActor in shared.handle(payload) }
        return true
    }

    /// The already-parsed variant. `handle(userInfo:)` funnels into this.
    public func handle(_ payload: PushPayload) {
        lastPayload = payload
        destination = Self.destination(for: payload)
        if payload.raisesDriverNudge { showDriverNudge = true }
        if payload.endsLiveActivity { onEndLiveActivity?() }
    }

    public func dismissDriverNudge() { showDriverNudge = false }

    /// Consumed by `ios7` once it has navigated, so a relaunch does not re-navigate.
    public func clearDestination() { destination = .ignore }

    // MARK: - The pure decision

    /// kind ⇒ screen. No side effects, no UIKit — this is the part the tests exercise.
    ///
    /// The three groups, straight off CLIENT_CONTRACT.md lines 50-52:
    ///   in-flight (`started`, `tenMin`, `leadTime`, `slip`, `runningLate`, `reply`)
    ///       ⇒ the live trip screen
    ///   terminal (`arrived`, `cancelled`, `timeout`, `lost`, `noShow`) ⇒ home
    ///   `armed` ⇒ home, because the receiver armed a spot and there is no trip screen yet
    ///   `didYouLeave` ⇒ the driver nudge sheet, over the trip screen
    ///   anything else ⇒ ignore
    /// `nonisolated` because it is genuinely pure — the delivery paths that call it are
    /// off the main actor, and so are the tests.
    public nonisolated static func destination(for payload: PushPayload) -> PushDestination {
        switch payload.kind {
        case .started, .tenMin, .leadTime, .slip, .runningLate, .reply:
            return .trip(tripId: payload.tripId)
        case .didYouLeave:
            return .driverNudge(tripId: payload.tripId)
        case .arrived, .cancelled, .timeout, .lost, .noShow, .armed:
            return .home
        case .unrecognised:
            return .ignore
        }
    }
}
