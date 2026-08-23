// ios/Headstart/UI/Components.swift
import SwiftUI

// Every measurement is lifted from the artboards: 56 pt controls with a 14 pt radius,
// 16 pt cards, 46 pt chips, 12 pt uppercase section labels tracked 1.4. Nothing
// interactive is under 44 pt. Colours come from `HS.*` only — never a hex literal here.

// MARK: - Buttons

public enum HSButtonKind {
    /// Green fill, dark ink — "Get started", "Send code", "I'm here", "Save spot".
    case primary
    /// Card fill with a hairline — "I have an invite code", "Copy code", "Sign out".
    case secondary
    /// Red outline, red label — "Delete my account and data", "Cancel the trip".
    case destructive
}

/// The 56 pt full-width control used on every screen. Disabled state is the
/// `#262A30` / `#6D7681` pair from `Verify.dc.html` and `PairEnter.dc.html`.
public struct HSButton: View {
    private let title: String
    private let kind: HSButtonKind
    private let systemImage: String?
    private let enabled: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        kind: HSButtonKind = .primary,
        systemImage: String? = nil,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.systemImage = systemImage
        self.enabled = enabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 18, weight: .semibold))
                }
                Text(title).font(.hs(17, weight))
            }
            .frame(maxWidth: .infinity)
            .frame(height: HS.controlHeight)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: HS.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HS.Radius.control, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var weight: Font.Weight { kind == .primary ? .semibold : .medium }

    private var foreground: Color {
        guard enabled else { return HS.text3 }
        switch kind {
        case .primary: return HS.goInk
        case .secondary: return HS.text
        case .destructive: return HS.delayed
        }
    }

    private var background: Color {
        guard enabled else { return HS.raised }
        switch kind {
        case .primary: return HS.go
        case .secondary: return HS.card
        case .destructive: return .clear
        }
    }

    private var border: Color {
        guard enabled else { return HS.line }
        switch kind {
        case .primary: return .clear
        case .secondary: return HS.line
        case .destructive: return HS.delayedEdge
        }
    }
}

// MARK: - Card

/// `#1E2126` fill, `#31363D` hairline, 16 pt radius — the container on almost every screen.
public struct HSCard<Content: View>: View {
    private let padding: CGFloat
    private let radius: CGFloat
    private let content: Content

    public init(
        padding: CGFloat = 18,
        radius: CGFloat = HS.Radius.card,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.radius = radius
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HS.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(HS.line, lineWidth: 1)
            )
    }
}

// MARK: - Chip

/// 46 pt pill — the quick-reply bar on `ReceiverTrip.dc.html`.
public struct HSChip: View {
    private let title: String
    private let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.hs(15, .medium))
                .foregroundStyle(HS.text)
                .padding(.horizontal, 18)
                .frame(height: 46)
                .background(HS.card)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(HS.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section label

/// "OTHER SPOTS", "QUICK REPLY" — 12 pt, 600, uppercase, tracked 1.4, `#6D7681`.
public struct HSSectionLabel: View {
    private let text: String
    private let color: Color

    public init(_ text: String, color: Color = HS.text3) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text.uppercased())
            .font(.hs(12, .semibold))
            .tracking(1.4)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Big ETA

/// The signature number: "18" + "min away" on `DriverTrip`, "7:20" + "until you walk out"
/// on `ReceiverTrip`. Always tabular so the digits do not jitter as it ticks.
public struct HSBigNumber: View {
    private let value: String
    private let unit: String
    private let size: CGFloat
    private let tracking: CGFloat
    private let color: Color

    public init(
        value: String,
        unit: String,
        size: CGFloat = 88,
        tracking: CGFloat = -4,
        color: Color = HS.text
    ) {
        self.value = value
        self.unit = unit
        self.size = size
        self.tracking = tracking
        self.color = color
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size >= 80 ? 12 : 11) {
            Text(value)
                .font(.hsNum(size, .bold))
                .tracking(tracking)
                .foregroundStyle(color)
            Text(unit)
                .font(.hs(size >= 80 ? 26 : 19, .medium))
                .foregroundStyle(HS.text2)
        }
    }
}

// MARK: - Progress bar

/// 8 pt track on `ReceiverTrip`, 7 pt in the Live Activity.
public struct HSProgressBar: View {
    private let fraction: Double
    private let height: CGFloat

    public init(fraction: Double, height: CGFloat = 8) {
        self.fraction = fraction
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(HS.raised)
                Capsule().fill(HS.go).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Navigation chrome

/// The 44 pt back chevron every pushed screen draws itself — the artboards have no
/// system navigation bar, so screens hide it and use this instead.
public struct HSBackBar: View {
    private let action: () -> Void

    public init(action: @escaping () -> Void) { self.action = action }

    public var body: some View {
        HStack {
            Button(action: action) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(HS.text2)
                    .frame(width: HS.minTouchTarget, height: HS.minTouchTarget, alignment: .leading)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(height: HS.minTouchTarget)
    }
}

/// The 44 pt circular gear on `DriverHome` / `ReceiverHome`.
public struct HSIconButton: View {
    private let systemImage: String
    private let tint: Color
    private let corner: CGFloat
    private let action: () -> Void

    public init(
        systemImage: String,
        tint: Color = HS.text2,
        corner: CGFloat = 22,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.corner = corner
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: HS.minTouchTarget, height: HS.minTouchTarget)
                .background(HS.card)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(HS.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// The shield + sentence that closes `DriverHome`, `ReceiverHome`, `PairEmpty`, `Phone`.
public struct HSPrivacyFooter: View {
    private let text: String
    private let centered: Bool

    public init(_ text: String, centered: Bool = true) {
        self.text = text
        self.centered = centered
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(HS.text3)
            Text(text)
                .font(.hs(13))
                .foregroundStyle(HS.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }
}

/// A tappable list row: icon tile, title, subtitle, chevron. Used by `Spots`,
/// `PairEmpty` and `DriverHome`'s "Other spots".
public struct HSListRow: View {
    private let systemImage: String?
    private let iconTint: Color
    private let title: String
    private let subtitle: String?
    private let trailingText: String?
    private let action: () -> Void

    public init(
        systemImage: String? = nil,
        iconTint: Color = HS.go,
        title: String,
        subtitle: String? = nil,
        trailingText: String? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.trailingText = trailingText
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(iconTint)
                        .frame(width: 42, height: 42)
                        .background(HS.raised)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.hs(17, .semibold)).foregroundStyle(HS.text)
                    if let subtitle {
                        Text(subtitle).font(.hs(14)).foregroundStyle(HS.text2)
                    }
                }
                Spacer(minLength: 8)
                if let trailingText {
                    Text(trailingText).font(.hs(14)).foregroundStyle(HS.text3)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HS.text3)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HS.card)
            .clipShape(RoundedRectangle(cornerRadius: HS.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HS.Radius.card, style: .continuous)
                    .strokeBorder(HS.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Screen scaffold: base background, dark scheme, 26 pt side padding, hidden nav bar.
public struct HSScreen<Content: View>: View {
    private let horizontalPadding: CGFloat
    private let content: Content

    public init(horizontalPadding: CGFloat = HS.screenPadding, @ViewBuilder content: () -> Content) {
        self.horizontalPadding = horizontalPadding
        self.content = content()
    }

    public var body: some View {
        ZStack {
            HS.base.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, horizontalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview("Components") {
    ScrollView {
        VStack(spacing: 16) {
            HSButton("Get started") {}
            HSButton("I have an invite code", kind: .secondary) {}
            HSButton("Verify", enabled: false) {}
            HSButton("Delete my account and data", kind: .destructive) {}
            HSSectionLabel("Other spots")
            HSListRow(systemImage: "house", title: "Office", subtitle: "Sara walks out 3 min early") {}
            HSBigNumber(value: "18", unit: "min away")
            HSBigNumber(value: "7:20", unit: "until you walk out", size: 56, tracking: -2.4)
            HSProgressBar(fraction: 0.53)
            HStack { HSChip("5 more min") {}; HSChip("Take your time") {} }
            HSPrivacyFooter("Nothing is shared until you tap")
        }
        .padding(26)
    }
    .background(HS.base)
    .preferredColorScheme(.dark)
}

#Preview("Chrome") {
    HSScreen {
        HSBackBar {}
        HStack {
            HSSectionLabel("Tuesday evening")
            Spacer()
            HSIconButton(systemImage: "gearshape") {}
        }
        .padding(.bottom, 18)
        HSCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Office").font(.hs(20, .semibold)).foregroundStyle(HS.text)
                Text("11.0 km · 5:48 pm").font(.hs(14)).foregroundStyle(HS.text2)
            }
        }
        Spacer()
        HSButton("I'm coming", systemImage: "car.fill") {}
    }
}
