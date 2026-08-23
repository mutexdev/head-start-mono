// ios/Headstart/LiveActivity/HeadstartActivityAttributes.swift
//
// Shared by the app target (which starts/updates/ends the activity) and the widget
// extension (which renders it). Both targets compile this same file, declared once in
// ios/project.yml under the widget target's `sources:` — never by ticking a Target
// Membership checkbox, which is unreachable from an automated pipeline.
//
// KEEP THIS FILE FOUNDATION + ACTIVITYKIT ONLY. The widget extension does not compile
// `Trip`, `SpotLimits` or anything else from Data/, so anything that touches a model
// belongs in LiveActivityController.swift (app target only) instead.
//
// Only two dates and a percentage cross the boundary: WidgetKit renders the ticking
// countdown itself from `walkOutAt` via `Text(timerInterval:)`, so the number on the Lock
// Screen moves at 1 Hz while the server stays silent until the ETA actually shifts.
import Foundation
import ActivityKit

/// The receiver's Live Activity: "they're X minutes away, walk out at HH:MM".
///
/// M1 STARTS THIS LOCALLY. The receiver's own app requests the Activity the moment it sees
/// its trip enter `driving`. There is no push-to-start and no remote update, because the
/// callable that would hand ActivityKit a start token is not part of the M1 surface
/// (docs/CLIENT_CONTRACT_ADDENDUM.md §A lists the twelve callables that are, and names the
/// three that are not). Consequence, stated plainly: if the receiver has force-quit the
/// app, no Live Activity appears for that trip. The `leadTime` push still fires, and that
/// is the alert the product actually rests on.
struct HeadstartActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// When the driver is expected at the spot.
        var arriveAt: Date
        /// When the receiver should start walking out (arriveAt − leadTimeMin).
        var walkOutAt: Date
        /// 0…100, mirrors `trip.receiverView.progressPct`.
        var progressPct: Int
        /// True when the ETA is a straight-line estimate rather than a routed one
        /// (`trip.eta.approximate`), so the UI can say "about".
        var approximate: Bool
    }

    /// The driver's display name, already resolved through `PartnerName`.
    var driverName: String
    /// The spot's name, from `trip.spot.name`.
    var spotName: String
}

/// The name the rest of the app uses. `HeadstartActivityAttributes.ContentState` is what
/// ActivityKit demands; `LiveActivityState` is what reads well at every call site.
typealias LiveActivityState = HeadstartActivityAttributes.ContentState

extension HeadstartActivityAttributes.ContentState {

    /// Builds the state from an ETA measured at `anchor` — the server's `eta.updatedAt`,
    /// NOT `Date.now`. Anchoring to the server's own measurement is what stops the
    /// countdown drifting by however long the document took to reach this device, and it
    /// is why two receivers looking at the same trip see the same number.
    static func make(
        etaSec: Int,
        leadTimeMin: Int,
        progressPct: Int,
        anchor: Date,
        approximate: Bool = false
    ) -> Self {
        Self(
            arriveAt: anchor.addingTimeInterval(Double(max(0, etaSec))),
            // Never before the anchor: an ETA already inside the lead time means "walk out
            // now", not "walk out two minutes ago", and a reversed date range would trap
            // `Text(timerInterval:)`.
            walkOutAt: anchor.addingTimeInterval(Double(max(0, etaSec - leadTimeMin * 60))),
            progressPct: min(100, max(0, progressPct)),
            approximate: approximate
        )
    }

    /// Mirrors the server's rule for emitting a Live Activity update: only when the target
    /// moved by at least a minute. Without it the Lock Screen repaints on every position
    /// upload, which is both ugly and a battery cost for zero information.
    func isWorthUpdating(to next: Self) -> Bool {
        abs(next.walkOutAt.timeIntervalSince(walkOutAt)) >= 60
            || abs(next.arriveAt.timeIntervalSince(arriveAt)) >= 60
    }
}
