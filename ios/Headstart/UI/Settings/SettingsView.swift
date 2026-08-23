// ios/Headstart/UI/Settings/SettingsView.swift
//
// `design/Settings.dc.html`. Six controls are drawn; FOUR work in M1 and two belong to
// later milestones. The two that do not work are still drawn exactly as the artboard has
// them and EXPLAIN THEMSELVES when tapped — a row that looks live and does nothing is
// worse than one that says why:
//
//   Trip history → Clear      positions already self-delete after 30 days via the
//                             Firestore TTL; a manual purge needs a callable that is not
//                             in the M1 surface (CLIENT_CONTRACT_ADDENDUM.md §A).
//   Delete my account and data  same — the account-deletion callable is not in M1 either,
//                             and no stub may sneak in, so this row only ever explains.
//
// "Loud walk-out alert" deep-links to iOS Settings on purpose. The alert's urgency is set
// server-side (`interruption-level: time-sensitive` on `leadTime`, and only on `leadTime`
// — ADDENDUM §C). The only switch a person actually owns is the system one.
//
// "Hide my exact position" is stored LOCALLY and passed as `startTrip({fuzzy:})`; the
// server then omits the point from `receiverView` until the ETA is under five minutes.
// That is the whole M1 implementation of fuzzy mode.
//
// `partnerName` is already resolved by the caller through `PartnerName.resolve(pair:selfUid:)`,
// like every other screen — never an optional, never a raw `memberNames` lookup, or this
// screen and the push copy disagree about what the other person is called.

import SwiftUI
import UIKit

/// The one persisted preference this screen owns. The key lives here, publicly, so
/// `AppViewModel` reads the SAME string when it builds `startTrip({fuzzy:})` — two
/// `@AppStorage` declarations with different literals would split the setting in two.
public enum PrivacySettings {
    public static let hideExactPositionKey = "headstart.hideExactPosition"

    /// What `startTrip` should send. `false` (share the exact dot) is the default.
    public static var hideExactPosition: Bool {
        UserDefaults.standard.bool(forKey: hideExactPositionKey)
    }
}

public struct SettingsView: View {

    @AppStorage(PrivacySettings.hideExactPositionKey) private var hideExactPosition = false

    @State private var confirmUnpair = false
    @State private var infoTitle: String?
    @State private var infoBody = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var testAlertSent = false

    private let partnerName: String
    private let pairedSince: Int64?
    private let onBack: () -> Void
    private let onUnpair: () async -> String?
    private let onTestAlert: () async -> String?
    private let onSignOut: () -> Void

    public init(
        partnerName: String = PartnerName.fallback,
        pairedSince: Int64? = nil,
        onBack: @escaping () -> Void,
        onUnpair: @escaping () async -> String?,
        onTestAlert: @escaping () async -> String?,
        onSignOut: @escaping () -> Void
    ) {
        self.partnerName = partnerName
        self.pairedSince = pairedSince
        self.onBack = onBack
        self.onUnpair = onUnpair
        self.onTestAlert = onTestAlert
        self.onSignOut = onSignOut
    }

    public var body: some View {
        HSScreen {
            Spacer().frame(height: 26)
            HSBackBar(action: onBack)
            Spacer().frame(height: 4)

            Text("Settings")
                .font(.hs(28, .bold))
                .tracking(-0.9)
                .foregroundStyle(HS.text)

            Spacer().frame(height: 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pairCard

                    Spacer().frame(height: 22)
                    HSSectionLabel("Privacy")
                    Spacer().frame(height: 12)
                    privacyGroup

                    Spacer().frame(height: 22)
                    HSSectionLabel("Notifications")
                    Spacer().frame(height: 12)
                    notificationsGroup

                    if let errorText {
                        Spacer().frame(height: 16)
                        Text(errorText)
                            .font(.hs(14))
                            .foregroundStyle(HS.delayed)
                    }

                    Spacer().frame(height: 28)
                    VStack(spacing: 11) {
                        HSButton("Sign out", kind: .secondary, enabled: !busy, action: onSignOut)
                        HSButton("Delete my account and data", kind: .destructive, enabled: !busy) {
                            explain(
                                "Not in this version yet",
                                "Deleting your account wipes your pairs, spots and trips everywhere, and that needs a server-side step we haven't shipped. Until then: unpair, then sign out. Location history already deletes itself after 30 days."
                            )
                        }
                    }
                    .padding(.bottom, 38)
                }
            }
            .scrollIndicators(.hidden)
        }
        .alert("Unpair?", isPresented: $confirmUnpair) {
            Button("Cancel", role: .cancel) {}
            Button("Unpair", role: .destructive) {
                busy = true
                Task {
                    errorText = await onUnpair()
                    busy = false
                }
            }
        } message: {
            Text("Trips, spots and alerts between you and \(PartnerCopy.mid(partnerName)) stop immediately. Either of you can pair again with a new code.")
        }
        .alert(infoTitle ?? "", isPresented: Binding(
            get: { infoTitle != nil },
            set: { if !$0 { infoTitle = nil } }
        )) {
            Button("OK", role: .cancel) { infoTitle = nil }
        } message: {
            Text(infoBody)
        }
    }

    // MARK: - Pair card

    private var pairCard: some View {
        HSCard(padding: 18, radius: 18) {
            HStack(spacing: 15) {
                Text(PartnerCopy.initial(partnerName))
                    .font(.hs(19, .semibold))
                    .foregroundStyle(HS.text2)
                    .frame(width: 50, height: 50)
                    .background(HS.raised)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Paired with \(PartnerCopy.mid(partnerName))")
                        .font(.hs(18, .semibold))
                        .foregroundStyle(HS.text)
                        .lineLimit(1)
                    if let pairedSince, pairedSince > 0 {
                        Text("since \(Self.monthDay(pairedSince))")
                            .font(.hs(14))
                            .foregroundStyle(HS.text3)
                    }
                }

                Spacer(minLength: 8)

                Button { confirmUnpair = true } label: {
                    Text("Unpair")
                        .font(.hs(14, .medium))
                        .foregroundStyle(HS.delayed)
                        .padding(.horizontal, 16)
                        .frame(height: HS.minTouchTarget)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(HS.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
    }

    // MARK: - Privacy

    private var privacyGroup: some View {
        group {
            row(
                title: "Hide my exact position",
                subtitle: "\(partnerName) sees the countdown but not the dot, until you're 5 min out."
            ) {
                Toggle("", isOn: $hideExactPosition)
                    .labelsHidden()
                    .tint(HS.go)
            }
            divider
            row(
                title: "Trip history",
                subtitle: "Deleted automatically after 30 days"
            ) {
                pillButton("Clear") {
                    explain(
                        "Already automatic",
                        "Every position is stamped with a 30-day expiry when it is written, and Firestore deletes it for you. A manual purge button arrives with account deletion."
                    )
                }
            }
        }
    }

    // MARK: - Notifications

    private var notificationsGroup: some View {
        group {
            row(
                title: "Loud walk-out alert",
                subtitle: "Own sound, breaks through Do Not Disturb"
            ) {
                pillButton("Open") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            divider
            Button {
                busy = true
                Task {
                    let failure = await onTestAlert()
                    errorText = failure
                    testAlertSent = failure == nil
                    busy = false
                }
            } label: {
                row(
                    title: "Send me a test alert",
                    subtitle: testAlertSent
                        ? "On its way — five seconds. Lock the phone to see it properly."
                        : "Check it actually gets through"
                ) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HS.text3)
                }
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
    }

    // MARK: - Pieces

    /// The grouped card the artboard draws twice: 18 pt radius, hairline, inset dividers.
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(HS.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(HS.line, lineWidth: 1)
            )
    }

    private var divider: some View {
        Rectangle().fill(HS.line).frame(height: 1).padding(.horizontal, 18)
    }

    private func row<Trailing: View>(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.hs(16, .semibold))
                    .foregroundStyle(HS.text)
                Text(subtitle)
                    .font(.hs(14))
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(HS.text2)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .contentShape(Rectangle())
    }

    /// The 44 pt raised pill the artboard uses for "Clear" and "Open".
    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.hs(14, .medium))
                .foregroundStyle(HS.text2)
                .padding(.horizontal, 16)
                .frame(height: HS.minTouchTarget)
                .background(HS.raised)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(HS.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func explain(_ title: String, _ body: String) {
        infoBody = body
        infoTitle = title
    }

    /// "12 August", as the artboard writes it.
    private static func monthDay(_ epochMs: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: Date(timeIntervalSince1970: Double(epochMs) / 1000))
    }
}

// MARK: - Previews

#Preview("Settings") {
    SettingsView(
        partnerName: "Sara",
        // 12 August 2026, the artboard's date.
        pairedSince: 1_786_000_000_000,
        onBack: {},
        onUnpair: { nil },
        onTestAlert: { nil },
        onSignOut: {}
    )
}

#Preview("Settings — unnamed partner, failing unpair") {
    SettingsView(
        onBack: {},
        onUnpair: { "Couldn't unpair. Check your connection and try again." },
        onTestAlert: { "Notifications are off for Headstart." },
        onSignOut: {}
    )
}
