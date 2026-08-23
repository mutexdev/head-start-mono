// ios/Headstart/UI/Driver/DriverHomeView.swift
import SwiftUI

// MARK: - Partner copy
//
// Shared by every Driver and Receiver screen in this batch, and defined here because
// `PartnerName` lives in Core/ and is owned by an earlier batch.
//
// The rule established in the previous batch is that a screen receives an ALREADY-RESOLVED
// `partnerName: String` — `PartnerName.resolve(pair:selfUid:)`, which never returns nil and
// falls back to the sentence-initial "Your partner". That is right for a headline and wrong in
// the middle of a sentence ("Ping me when Your partner leaves"), so this is the one adjustment
// the screens make to it. Nothing else: no truncation, no capitalisation fixing, no
// pluralisation — the string is whatever the person typed on the profile screen, and the
// server already bounds its length.
public enum PartnerCopy {

    /// Mid-sentence form: "…when Sara leaves", "…when your partner leaves".
    public static func mid(_ name: String) -> String {
        name == PartnerName.fallback ? "your partner" : name
    }

    /// Possessive: "Sara's", "your partner's".
    public static func possessive(_ name: String) -> String { "\(mid(name))'s" }

    /// The letter in the reply avatar. Empty names cannot occur — `PartnerName.resolve`
    /// guarantees a non-empty string — but this stays total anyway.
    public static func initial(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

// MARK: - Role switch
//
// DELIBERATE DEVIATION FROM THE ARTBOARDS, agreed platform-wide (iOS plan doc line 81, and
// Android does the same): `DriverHome.dc.html` and `ReceiverHome.dc.html` are drawn as two
// unconnected screens with no way to move between them. But either paired person can drive —
// that is the whole premise — so Home carries a 44 pt segmented control and remembers the last
// choice in `@AppStorage`.
//
// This is a control, not a screen: it is the ONE place in the UI layer that owns persistent
// state, because the choice must survive a relaunch and there is nowhere else for it to live
// until `AppViewModel` exists. `DriverHomeView` and `ReceiverHomeView` stay stateless; the
// composing screen stacks this above whichever of them `role` selects.

public enum HomeRole: String, CaseIterable, Sendable, Equatable {
    case driving
    case waiting

    /// Also read by `AppViewModel` in a later batch — same key, same values, one truth.
    public static let storageKey = "headstart.role"
}

public struct HomeRoleSwitch: View {

    @AppStorage(HomeRole.storageKey) private var stored = HomeRole.driving.rawValue

    /// An active trip forces the matching role: the driver cannot flip to "I'm waiting" while
    /// their own position is uploading, and the receiver cannot pretend to be driving. nil when
    /// no trip is running, and the control is then free.
    private let forced: HomeRole?
    private let onChange: ((HomeRole) -> Void)?

    public init(forced: HomeRole? = nil, onChange: ((HomeRole) -> Void)? = nil) {
        self.forced = forced
        self.onChange = onChange
    }

    /// The role the app should render right now.
    public var role: HomeRole { forced ?? HomeRole(rawValue: stored) ?? .driving }

    public var body: some View {
        Picker("", selection: Binding(
            get: { role },
            set: { newValue in
                guard forced == nil else { return }
                stored = newValue.rawValue
                onChange?(newValue)
            }
        )) {
            Text("I'm driving").tag(HomeRole.driving)
            Text("I'm waiting").tag(HomeRole.waiting)
        }
        .pickerStyle(.segmented)
        .frame(height: HS.minTouchTarget)
        .disabled(forced != nil)
        .opacity(forced == nil ? 1 : 0.55)
        .accessibilityLabel("Driving or waiting")
    }
}

// MARK: - Driver home

/// `design/DriverHome.dc.html`. The whole product is the big green card: one tap, and
/// nothing at all is shared before it.
///
/// `partnerName` is already resolved by the caller through `PartnerName.resolve(pair:selfUid:)`.
/// `onStart` returns an error message to render inline, or nil on success — the caller is what
/// turns a `HeadstartError` into that string, so no raw NSError text can reach this screen.
public struct DriverHomeView: View {

    @State private var busySpotId: String?
    @State private var errorText: String?

    private let myName: String
    private let partnerName: String
    private let spots: [Spot]
    /// Set when the receiver has armed a trip ("ping me when you leave").
    private let armedSpotName: String?
    private let onSettings: () -> Void
    private let onStart: (Spot) async -> String?
    private let onManageSpots: () -> Void

    public init(
        myName: String,
        partnerName: String = PartnerName.fallback,
        spots: [Spot],
        armedSpotName: String? = nil,
        onSettings: @escaping () -> Void,
        onStart: @escaping (Spot) async -> String?,
        onManageSpots: @escaping () -> Void
    ) {
        self.myName = myName
        self.partnerName = partnerName
        self.spots = spots
        self.armedSpotName = armedSpotName
        self.onSettings = onSettings
        self.onStart = onStart
        self.onManageSpots = onManageSpots
    }

    private var primary: Spot? { spots.first }
    private var others: [Spot] { Array(spots.dropFirst()) }
    private var busy: Bool { busySpotId != nil }

    public var body: some View {
        HSScreen {
            Spacer().frame(height: 34)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greetingFor())
                        .font(.hs(15))
                        .foregroundStyle(HS.text3)
                    Text(myName.isEmpty ? "Where to?" : "Where to, \(myName)?")
                        .font(.hs(28, .bold))
                        .tracking(-0.9)
                        .foregroundStyle(HS.text)
                }
                Spacer()
                HSIconButton(systemImage: "gearshape", action: onSettings)
                    .accessibilityLabel("Settings")
            }

            if let armedSpotName {
                Spacer().frame(height: 20)
                armedBanner(spotName: armedSpotName)
            }

            Spacer().frame(height: 22)

            if let primary {
                primaryCard(primary)
            } else {
                emptyCard
            }

            if let errorText {
                Spacer().frame(height: 14)
                Text(errorText).font(.hs(14)).foregroundStyle(HS.delayed)
            }

            Spacer().frame(height: 24)

            if !others.isEmpty {
                HStack {
                    HSSectionLabel("Other spots")
                    Spacer()
                    Button("Manage", action: onManageSpots)
                        .font(.hs(13, .semibold))
                        .foregroundStyle(HS.go)
                        .buttonStyle(.plain)
                        .frame(height: HS.minTouchTarget)
                }

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(others) { spot in
                            otherSpotRow(spot)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            Spacer()

            HSPrivacyFooter("Nothing is shared until you tap")
                .padding(.bottom, 44)
        }
    }

    // MARK: -

    private func armedBanner(spotName: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Circle().fill(HS.headstart).frame(width: 8, height: 8).padding(.top, 7)
            (
                Text("\(partnerName) is waiting at ").foregroundStyle(HS.text)
                + Text(spotName).font(.hs(15, .semibold)).foregroundStyle(HS.text)
                + Text(" — they asked for a ping when you leave.").foregroundStyle(HS.text2)
            )
            .font(.hs(15))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(HS.headstartWash)
        .clipShape(RoundedRectangle(cornerRadius: HS.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HS.Radius.card, style: .continuous)
                .strokeBorder(HS.headstartEdge, lineWidth: 1)
        )
    }

    private func primaryCard(_ spot: Spot) -> some View {
        Button { start(spot) } label: {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Tap once — that's it")
                        .font(.hs(13, .bold))
                        .tracking(1.4)
                        .foregroundStyle(HS.goInk.opacity(0.62))
                    Spacer()
                    Image(systemName: "car.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(HS.goInk.opacity(0.62))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("I'm coming")
                        .font(.hs(34, .bold))
                        .tracking(-1.3)
                        .foregroundStyle(HS.goInk)
                    Text("to \(spot.name) — \(PartnerCopy.mid(partnerName)) gets \(spot.leadTimeMin) min")
                        .font(.hs(19, .medium))
                        .foregroundStyle(HS.goInk.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HS.go)
            .clipShape(RoundedRectangle(cornerRadius: HS.Radius.bigCard, style: .continuous))
            .opacity(busySpotId == spot.id ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("I'm coming to \(spot.name)")
    }

    private var emptyCard: some View {
        HSCard(padding: 22, radius: HS.Radius.bigCard) {
            VStack(alignment: .leading, spacing: 10) {
                Text("No pickup spot yet")
                    .font(.hs(20, .bold))
                    .foregroundStyle(HS.text)
                Text("Add the place you pick them up from and the big button appears here.")
                    .font(.hs(15))
                    .lineSpacing(3)
                    .foregroundStyle(HS.text2)
                HSButton("Add a spot", kind: .secondary, action: onManageSpots)
                    .padding(.top, 6)
            }
        }
    }

    private func otherSpotRow(_ spot: Spot) -> some View {
        Button { start(spot) } label: {
            HStack(spacing: 14) {
                Text(spot.name)
                    .font(.hs(16, .semibold))
                    .foregroundStyle(HS.text)
                Spacer(minLength: 8)
                Text("\(spot.leadTimeMin) min")
                    .font(.hsNum(14, .regular))
                    .foregroundStyle(HS.text3)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HS.text3)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(HS.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(HS.line, lineWidth: 1)
            )
            .opacity(busySpotId == spot.id ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func start(_ spot: Spot) {
        guard !busy else { return }
        busySpotId = spot.id
        errorText = nil
        Task {
            errorText = await onStart(spot)
            busySpotId = nil
        }
    }
}

// MARK: - Previews

#Preview("Driver home") {
    DriverHomeView(
        myName: "Mostafi",
        partnerName: "Sara",
        spots: SpotPreviewData.all,
        onSettings: {},
        onStart: { _ in nil },
        onManageSpots: {}
    )
}

#Preview("Driver home — armed by the receiver") {
    DriverHomeView(
        myName: "Mostafi",
        partnerName: "Sara",
        spots: SpotPreviewData.all,
        armedSpotName: "Office",
        onSettings: {},
        onStart: { _ in nil },
        onManageSpots: {}
    )
}

#Preview("Driver home — no spots, unnamed partner") {
    DriverHomeView(
        myName: "Mostafi",
        spots: [],
        onSettings: {},
        onStart: { _ in nil },
        onManageSpots: {}
    )
}

#Preview("Driver home — startTrip failed") {
    DriverHomeView(
        myName: "Mostafi",
        partnerName: "Sara",
        spots: SpotPreviewData.all,
        onSettings: {},
        onStart: { _ in HeadstartError.tripActive.userMessage },
        onManageSpots: {}
    )
}

#Preview("Role switch") {
    VStack(spacing: 22) {
        HomeRoleSwitch()
        HomeRoleSwitch(forced: .driving)
        HomeRoleSwitch(forced: .waiting)
    }
    .padding(HS.screenPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HS.base)
    .preferredColorScheme(.dark)
}
