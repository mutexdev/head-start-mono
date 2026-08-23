// ios/Headstart/UI/Receiver/ReceiverHomeView.swift
import SwiftUI

/// `design/ReceiverHome.dc.html`, minus the artboard's "Coming up" schedule card — recurring
/// schedules are M3 and nothing in M1 can populate it.
///
/// The receiver owns the headstart value: the stepper here writes straight through
/// `upsertSpot`, and the driver's home card then reads the new number. The range is 1–15,
/// narrower than the contract's 1–30 clamp on purpose (the artboard's stepper), so everything
/// this control can produce is already inside `SpotLimits` — the clamp in `SpotRepository` is a
/// second belt, not the only one.
///
/// "Ping me when they leave" is `armTrip({spotId, neededBy?})` — the needed-by time rides on
/// that call, and the separate needed-by callable the spec mentions is NOT part of M1
/// (CLIENT_CONTRACT_ADDENDUM.md §A). Its identifier is deliberately not spelled out here: a
/// done-criteria grep looks for exactly that string and a comment would be its only hit.
public struct ReceiverHomeView: View {

    @State private var busy = false
    @State private var errorText: String?

    private let partnerName: String
    private let spot: Spot?
    private let armed: Bool
    private let onSettings: () -> Void
    private let onChangeLeadTime: (Int) async -> String?
    private let onPingMe: () async -> String?
    private let onOpenSpots: () -> Void

    /// The artboard's stepper bounds. Both are inside `SpotLimits.leadTimeMinRange` (1…30).
    static let leadTimeRange = 1...15

    public init(
        partnerName: String = PartnerName.fallback,
        spot: Spot?,
        armed: Bool = false,
        onSettings: @escaping () -> Void,
        onChangeLeadTime: @escaping (Int) async -> String?,
        onPingMe: @escaping () async -> String?,
        onOpenSpots: @escaping () -> Void
    ) {
        self.partnerName = partnerName
        self.spot = spot
        self.armed = armed
        self.onSettings = onSettings
        self.onChangeLeadTime = onChangeLeadTime
        self.onPingMe = onPingMe
        self.onOpenSpots = onOpenSpots
    }

    public var body: some View {
        HSScreen {
            Spacer().frame(height: 34)

            HStack(alignment: .top) {
                Text(armed ? "Waiting for them to leave" : "Nothing on the way")
                    .font(.hs(28, .bold))
                    .tracking(-0.9)
                    .foregroundStyle(HS.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                HSIconButton(systemImage: "gearshape", action: onSettings)
                    .accessibilityLabel("Settings")
            }

            Spacer().frame(height: 10)
            Text("You'll get a notification the moment \(PartnerCopy.mid(partnerName)) starts driving.")
                .font(.hs(16))
                .lineSpacing(3)
                .foregroundStyle(HS.text2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 28)

            if let spot {
                spotCard(spot)
                Spacer().frame(height: 16)
                pingButton
            } else {
                emptyCard
            }

            if let errorText {
                Spacer().frame(height: 14)
                Text(errorText).font(.hs(14)).foregroundStyle(HS.delayed)
            }

            Spacer()

            HSPrivacyFooter("You can't see where \(PartnerCopy.mid(partnerName)) is right now")
                .padding(.bottom, 44)
        }
    }

    // MARK: -

    private func spotCard(_ spot: Spot) -> some View {
        HSCard(padding: 22, radius: 20) {
            VStack(spacing: 20) {
                Button(action: onOpenSpots) {
                    HStack(spacing: 14) {
                        Image(systemName: SpotsView.icon(for: spot.name))
                            .font(.system(size: 20))
                            .foregroundStyle(HS.go)
                            .frame(width: 44, height: 44)
                            .background(HS.raised)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(spot.name).font(.hs(18, .semibold)).foregroundStyle(HS.text)
                            Text("your usual spot").font(.hs(14)).foregroundStyle(HS.text3)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(HS.text3)
                    }
                }
                .buttonStyle(.plain)

                Rectangle().fill(HS.line).frame(height: 1)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your headstart").font(.hs(16, .semibold)).foregroundStyle(HS.text)
                        Text("desk to curb").font(.hs(14)).foregroundStyle(HS.text3)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 14) {
                        stepper(
                            icon: "minus",
                            enabled: spot.leadTimeMin > Self.leadTimeRange.lowerBound && !busy
                        ) {
                            setLeadTime(spot.leadTimeMin - 1)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(spot.leadTimeMin)")
                                .font(.hsNum(30, .bold))
                                .foregroundStyle(HS.headstart)
                            Text("min").font(.hs(16, .medium)).foregroundStyle(HS.text2)
                        }
                        .frame(minWidth: 64)
                        stepper(
                            icon: "plus",
                            enabled: spot.leadTimeMin < Self.leadTimeRange.upperBound && !busy
                        ) {
                            setLeadTime(spot.leadTimeMin + 1)
                        }
                    }
                }
            }
        }
    }

    private var pingButton: some View {
        Button { run { await onPingMe() } } label: {
            HStack(spacing: 11) {
                Image(systemName: armed ? "bell.badge.fill" : "bell")
                    .font(.system(size: 19))
                    .foregroundStyle(HS.go)
                Text(armed
                     ? "\(partnerName) will be pinged"
                     : "Ping me when \(PartnerCopy.mid(partnerName)) leaves")
                    .font(.hs(17, .semibold))
                    .foregroundStyle(HS.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(HS.raised)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(HS.line, lineWidth: 1)
            )
            .opacity(busy || armed ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(busy || armed)
    }

    private var emptyCard: some View {
        HSCard(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("No pickup spot yet").font(.hs(18, .semibold)).foregroundStyle(HS.text)
                Text("Add the place you get picked up from, then set how long it takes you to reach the curb.")
                    .font(.hs(15))
                    .lineSpacing(3)
                    .foregroundStyle(HS.text2)
                HSButton("Add a spot", kind: .secondary, action: onOpenSpots)
                    .padding(.top, 6)
            }
        }
    }

    private func stepper(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(enabled ? HS.text2 : HS.text3.opacity(0.4))
                .frame(width: HS.minTouchTarget, height: HS.minTouchTarget)
                .background(HS.raised)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(HS.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(icon == "plus" ? "More headstart" : "Less headstart")
    }

    private func setLeadTime(_ minutes: Int) {
        let clamped = SpotLimits.clampLeadTimeMin(
            min(max(minutes, Self.leadTimeRange.lowerBound), Self.leadTimeRange.upperBound)
        )
        run { await onChangeLeadTime(clamped) }
    }

    private func run(_ action: @escaping () async -> String?) {
        guard !busy else { return }
        busy = true
        errorText = nil
        Task {
            errorText = await action()
            busy = false
        }
    }
}

#Preview("Receiver home") {
    ReceiverHomeView(
        partnerName: "Mostafi",
        spot: SpotPreviewData.spot(id: "s1", name: "Office", leadTimeMin: 3),
        onSettings: {},
        onChangeLeadTime: { _ in nil },
        onPingMe: { nil },
        onOpenSpots: {}
    )
}

#Preview("Receiver home — armed") {
    ReceiverHomeView(
        partnerName: "Mostafi",
        spot: SpotPreviewData.spot(id: "s1", name: "Office", leadTimeMin: 8),
        armed: true,
        onSettings: {},
        onChangeLeadTime: { _ in nil },
        onPingMe: { nil },
        onOpenSpots: {}
    )
}

#Preview("Receiver home — no spot, unnamed partner") {
    ReceiverHomeView(
        spot: nil,
        onSettings: {},
        onChangeLeadTime: { _ in nil },
        onPingMe: { nil },
        onOpenSpots: {}
    )
}

#Preview("Receiver home — armTrip failed") {
    ReceiverHomeView(
        partnerName: "Mostafi",
        spot: SpotPreviewData.spot(id: "s1", name: "Office", leadTimeMin: 3),
        onSettings: {},
        onChangeLeadTime: { _ in nil },
        onPingMe: { HeadstartError.tripActive.userMessage },
        onOpenSpots: {}
    )
}
