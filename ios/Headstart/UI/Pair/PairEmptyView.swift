// ios/Headstart/UI/Pair/PairEmptyView.swift
import SwiftUI

/// `design/PairEmpty.dc.html`.
public struct PairEmptyView: View {

    private let onInvite: () -> Void
    private let onEnterCode: () -> Void

    public init(onInvite: @escaping () -> Void, onEnterCode: @escaping () -> Void) {
        self.onInvite = onInvite
        self.onEnterCode = onEnterCode
    }

    public var body: some View {
        HSScreen {
            Spacer().frame(height: 98)

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(HS.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(HS.line, lineWidth: 1)
                    )
                Image(systemName: "person.2")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(HS.go)
            }
            .frame(width: 78, height: 78)
            .accessibilityHidden(true)

            Spacer().frame(height: 26)
            Text("Pair with one person")
                .font(.hs(30, .bold))
                .tracking(-1)
                .foregroundStyle(HS.text)
            Spacer().frame(height: 12)
            Text("Headstart works between two people at a time. Either of you can be the one driving.")
                .font(.hs(16))
                .lineSpacing(4)
                .foregroundStyle(HS.text2)

            Spacer().frame(height: 38)

            VStack(spacing: 12) {
                actionRow(
                    icon: "plus",
                    iconForeground: HS.goInk,
                    iconBackground: HS.go,
                    title: "Invite someone",
                    subtitle: "Send a code or a link",
                    action: onInvite
                )
                actionRow(
                    icon: "rectangle.and.pencil.and.ellipsis",
                    iconForeground: HS.text2,
                    iconBackground: HS.raised,
                    title: "Enter a code",
                    subtitle: "Someone already invited you",
                    action: onEnterCode
                )
            }

            Spacer()

            HSPrivacyFooter(
                "Either of you can unpair at any moment, from either phone.",
                centered: false
            )
            .padding(.bottom, 44)
        }
    }

    private func actionRow(
        icon: String,
        iconForeground: Color,
        iconBackground: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconForeground)
                    .frame(width: HS.minTouchTarget, height: HS.minTouchTarget)
                    .background(iconBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.hs(17, .semibold)).foregroundStyle(HS.text)
                    Text(subtitle).font(.hs(14)).foregroundStyle(HS.text2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HS.text3)
            }
            .padding(20)
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

#Preview("Pair — empty") {
    PairEmptyView(onInvite: {}, onEnterCode: {})
}
