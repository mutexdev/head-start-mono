// ios/HeadstartWidget/TripLiveActivity.swift
//
// `design/LiveActivity.dc.html` — the Lock Screen card, the Dynamic Island expanded
// presentation, and the compact/minimal ones.
//
// EVERY COUNTDOWN IS `Text(timerInterval:)`. WidgetKit renders a self-updating timer from
// a `Date` range entirely on-device, so the Lock Screen ticks at 1 Hz while the server
// stays silent until the ETA actually moves by 60 s. Nothing here re-renders on a push.
//
// A reversed range traps `Text(timerInterval:)`, and `walkOutAt` legitimately falls into
// the past the moment the receiver should already be walking — hence `countdown(to:)`.

import SwiftUI
import WidgetKit
import ActivityKit

struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HeadstartActivityAttributes.self) { context in
            LockScreenCard(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(HS.card)
                .activitySystemActionForegroundColor(HS.text)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WalkOutTile()
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Walk out in")
                            .font(.hs(15, .semibold))
                            .foregroundStyle(HS.text)
                        Text("\(context.attributes.driverName) · \(context.attributes.spotName)")
                            .font(.hs(13))
                            .foregroundStyle(HS.text3)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: countdown(to: context.state.walkOutAt), countsDown: true)
                        .font(.hsNum(30, .bold))
                        .tracking(-1)
                        .foregroundStyle(HS.text)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 96, alignment: .trailing)
                }
            } compactLeading: {
                ChevronMark(size: 15)
            } compactTrailing: {
                Text(timerInterval: countdown(to: context.state.walkOutAt), countsDown: true)
                    .font(.hsNum(15, .bold))
                    .foregroundStyle(HS.headstart)
                    .monospacedDigit()
                    .frame(maxWidth: 50)
            } minimal: {
                ChevronMark(size: 14, tint: HS.headstart)
            }
            .keylineTint(HS.go)
        }
    }
}

// MARK: - Lock Screen
//
// A separate `View` rather than a method on the widget so it can be rendered by a plain
// `#Preview` as well as by the Live Activity preview macro.

struct LockScreenCard: View {
    let attributes: HeadstartActivityAttributes
    let state: LiveActivityState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                ChevronMark(size: 20)
                Text("Headstart")
                    .font(.hs(14, .semibold))
                    .foregroundStyle(HS.text2)
                Spacer(minLength: 8)
                Text(attributes.spotName)
                    .font(.hs(13))
                    .foregroundStyle(HS.text3)
                    .lineLimit(1)
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Walk out in")
                        .font(.hs(12, .bold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(HS.headstart)
                    Text(timerInterval: countdown(to: state.walkOutAt), countsDown: true)
                        .font(.hsNum(44, .bold))
                        .tracking(-1.8)
                        .foregroundStyle(HS.text)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    // "about" only when the server said the ETA is a straight-line guess
                    // rather than a routed one (`trip.eta.approximate`).
                    Text(state.approximate
                         ? "\(attributes.driverName) arrives about"
                         : "\(attributes.driverName) arrives")
                        .font(.hs(13))
                        .foregroundStyle(HS.text3)
                        .lineLimit(1)
                    Text(state.arriveAt, style: .time)
                        .font(.hsNum(20, .semibold))
                        .foregroundStyle(HS.text)
                        .monospacedDigit()
                }
            }

            ProgressRail(pct: state.progressPct)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
}

// MARK: - Parts

/// The 7 pt rail from the artboard. `GeometryReader`-free so it composes inside the
/// Dynamic Island's fixed-height regions without collapsing.
private struct ProgressRail: View {
    let pct: Int

    var body: some View {
        let fraction = min(1, max(0, Double(pct) / 100))
        return Capsule()
            .fill(HS.raised)
            .frame(height: 7)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(HS.go)
                        .frame(width: geo.size.width * fraction, height: 7)
                }
            }
    }
}

/// The Headstart mark: a dot and a forward chevron, both `HS.go` — the same glyph the
/// artboard draws as inline SVG.
private struct ChevronMark: View {
    var size: CGFloat = 20
    var tint: Color = HS.go

    var body: some View {
        Image(systemName: "chevron.forward.circle.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(tint)
    }
}

/// The 44 pt amber tile with the walking figure, from the expanded Dynamic Island.
private struct WalkOutTile: View {
    var body: some View {
        Image(systemName: "figure.walk")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(HS.headstartInk)
            .frame(width: 44, height: 44)
            .background(HS.headstart)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

/// A never-reversed range for `Text(timerInterval:)`. Once `walkOutAt` is in the past the
/// timer pins at 0:00, which is exactly the "walk out NOW" state the artboard wants.
private func countdown(to date: Date) -> ClosedRange<Date> {
    let now = Date.now
    return now...max(date, now)
}

// MARK: - Previews
//
// The only rendering proof available on this machine: no simulator shows a real Lock
// Screen Live Activity or a Dynamic Island. Compare against design/LiveActivity.dc.html —
// amber tracked eyebrow, 44 pt tabular countdown, 20 pt right-aligned arrival, 7 pt rail.

extension HeadstartActivityAttributes {
    static let preview = HeadstartActivityAttributes(driverName: "Mostafi", spotName: "Office")
}

extension LiveActivityState {
    /// 7:20 to walk out, 53 % of the way — the artboard's exact numbers.
    static let previewFar = LiveActivityState(
        arriveAt: .now.addingTimeInterval(620),
        walkOutAt: .now.addingTimeInterval(440),
        progressPct: 53,
        approximate: false
    )

    /// Already inside the lead time: the countdown is pinned and the bar is nearly full.
    static let previewNow = LiveActivityState(
        arriveAt: .now.addingTimeInterval(90),
        walkOutAt: .now.addingTimeInterval(-30),
        progressPct: 94,
        approximate: true
    )
}

#Preview("Lock Screen card", traits: .sizeThatFitsLayout) {
    VStack(spacing: 14) {
        LockScreenCard(attributes: .preview, state: .previewFar)
        LockScreenCard(attributes: .preview, state: .previewNow)
    }
    .background(HS.card)
    .environment(\.colorScheme, .dark)
}

#Preview("Live Activity", as: .content, using: HeadstartActivityAttributes.preview) {
    TripLiveActivity()
} contentStates: {
    LiveActivityState.previewFar
    LiveActivityState.previewNow
}

#Preview("Dynamic Island (expanded)", as: .dynamicIsland(.expanded), using: HeadstartActivityAttributes.preview) {
    TripLiveActivity()
} contentStates: {
    LiveActivityState.previewFar
}

#Preview("Dynamic Island (compact)", as: .dynamicIsland(.compact), using: HeadstartActivityAttributes.preview) {
    TripLiveActivity()
} contentStates: {
    LiveActivityState.previewFar
}
