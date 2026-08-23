// ios/Headstart/LiveActivity/LiveActivityController.swift
//
// Starts, updates and ends the receiver's Live Activity from the trip stream. App target
// only — the widget extension renders the Activity, it never drives one.
//
// HOW THIS IS PROVEN WITHOUT A LOCK SCREEN. A simulator cannot show a real Live Activity
// or a Dynamic Island, and there is no phone here, so the visual is genuinely unverified
// and is listed as such in docs/testing/real-drive-checklist.md. What IS verified:
//
//   (a) `LiveActivityStateTests` covers the pure state maths — the anchor, the lead-time
//       subtraction, the clamp and the 60-second update threshold;
//   (b) every lifecycle transition emits `[HS][la] started|updated|ended id=…`, which the
//       end-to-end drive asserts from `xcrun simctl spawn <udid> log stream`;
//   (c) the widget's `#Preview`s render both presentations in a canvas.
//
// Nothing here fakes a passing test for the visual.

import Foundation
import ActivityKit

// MARK: - Building the state from a trip document
//
// Deliberately NOT in HeadstartActivityAttributes.swift: that file compiles into the
// widget extension too, and the widget target has no `Trip`.

extension HeadstartActivityAttributes.ContentState {

    /// nil when the trip has no server ETA yet — there is nothing to count down to, and a
    /// Live Activity showing 0:00 is worse than no Live Activity.
    static func make(trip: Trip) -> Self? {
        guard let eta = trip.eta else { return nil }
        let anchor = Date(timeIntervalSince1970: Double(eta.updatedAt) / 1000)
        return make(
            // The receiver's own projection wins when the server has published one:
            // `receiverView` is the only position surface a receiver may read (ADDENDUM §H).
            etaSec: trip.receiverView?.etaSeconds ?? eta.seconds,
            leadTimeMin: trip.leadTimeMin,
            progressPct: trip.receiverView?.progressPct ?? 0,
            anchor: anchor,
            approximate: eta.approximate
        )
    }
}

/// ActivityKit's `Activity` is thread-safe by construction — `update` and `end` are
/// `nonisolated async` and the framework serialises them itself — but it is not marked
/// `Sendable`, so Swift 6 refuses to let a main-actor-isolated reference reach either of
/// them ("sending main actor-isolated 'activity' to nonisolated instance method").
///
/// This box carries exactly that one reference across the boundary and exposes nothing
/// mutable. It is the SECOND `@unchecked Sendable` in the app, after `ListenerBox` in
/// FirestoreStreams.swift; both exist for the same reason — an Apple type that is
/// documented as safe but predates `Sendable` annotation. Do not add a third without the
/// same justification.
private struct ActivityHandle: @unchecked Sendable {
    let activity: Activity<HeadstartActivityAttributes>

    var state: LiveActivityState { activity.content.state }

    func update(to state: LiveActivityState) async {
        await activity.update(ActivityContent(state: state, staleDate: state.arriveAt))
    }

    func end() async {
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}

@MainActor
public final class LiveActivityController: ObservableObject {

    public static let shared = LiveActivityController()

    private var activity: ActivityHandle?
    private var activityTripId: String?

    public init() {}

    /// False when the user turned Live Activities off in Settings → Headstart, or when the
    /// device does not support them at all. Every entry point checks it, so a disabled
    /// device silently does nothing instead of logging an error on every position.
    public var isSupported: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// The tripId this controller currently has an Activity for, or nil. Test/inspection seam.
    public var currentTripId: String? { activityTripId }

    /// Called on every trip snapshot the RECEIVER sees. Idempotent in both directions:
    /// starting twice for the same trip is a no-op, and an update that moves the target by
    /// under a minute is dropped (`isWorthUpdating`).
    ///
    /// Everything that is not "my live driving trip" ends the Activity. That single rule
    /// covers arrival, cancellation, timeout, the trip document disappearing, and the user
    /// signing out — there is no separate teardown path to forget to call.
    public func sync(trip: Trip?, myUid: String, partnerName: String) {
        guard isSupported else { return }

        guard let trip,
              trip.receiverUid == myUid,
              trip.state == .driving,
              let state = LiveActivityState.make(trip: trip)
        else {
            end()
            return
        }

        if activityTripId != trip.id {
            end()
            start(trip: trip, state: state, partnerName: partnerName)
            return
        }

        guard let activity, activity.state.isWorthUpdating(to: state) else { return }
        let tripId = trip.id
        Task {
            await activity.update(to: state)
            NSLog("[HS][la] updated id=\(tripId) walkOutAt=\(Int(state.walkOutAt.timeIntervalSince1970))")
        }
    }

    private func start(trip: Trip, state: LiveActivityState, partnerName: String) {
        let attributes = HeadstartActivityAttributes(
            driverName: partnerName,
            spotName: trip.spot.name
        )
        do {
            activity = ActivityHandle(activity: try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: state.arriveAt),
                // No push token: M1 starts and updates the Activity locally
                // (ADDENDUM §A — the token-registering callable is not in the M1 surface).
                pushType: nil
            ))
            activityTripId = trip.id
            NSLog("[HS][la] started id=\(trip.id) spot=\(trip.spot.name) walkOutAt=\(Int(state.walkOutAt.timeIntervalSince1970))")
        } catch {
            activity = nil
            activityTripId = nil
            NSLog("[HS][la] could not start: \(error.localizedDescription)")
        }
    }

    /// Safe to call when nothing is running. Also wired to `PushRouter.onEndLiveActivity`,
    /// because a terminal push can arrive while the trip listener is detached.
    public func end() {
        guard let activity else {
            activityTripId = nil
            return
        }
        let tripId = activityTripId ?? "-"
        self.activity = nil
        activityTripId = nil
        Task {
            await activity.end()
            NSLog("[HS][la] ended id=\(tripId)")
        }
    }
}
