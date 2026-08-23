// ios/Headstart/UI/Onboarding/ProfileView.swift
import SwiftUI

/// `design/Profile.dc.html`. The name and the two permission primers in one screen, because
/// both are things we must ask for exactly once and explain before asking.
///
/// The name typed here is what the OTHER person sees in every alert: the backend denormalises
/// it onto `pairs/{id}.memberNames` (ADDENDUM §M) and `PartnerName` resolves it. A name left
/// blank is not a broken screen — it renders as "Your partner" everywhere — but the button
/// stays disabled anyway, because a name is cheap here and impossible to ask for later.
public struct ProfileView: View {

    @State private var name: String
    @State private var busy = false
    @State private var errorText: String?
    @FocusState private var nameFocused: Bool

    private let onBack: () -> Void
    private let onContinue: (String) async -> String?

    /// - Parameter onContinue: receives the trimmed name; returns an error message, or nil.
    public init(
        name: String = "",
        onBack: @escaping () -> Void,
        onContinue: @escaping (String) async -> String?
    ) {
        _name = State(initialValue: name)
        self.onBack = onBack
        self.onContinue = onContinue
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var body: some View {
        HSScreen {
            Spacer().frame(height: 26)
            HSBackBar(action: onBack)
            Spacer().frame(height: 24)

            Text("Two last things")
                .font(.hs(30, .bold))
                .tracking(-1)
                .foregroundStyle(HS.text)
            Spacer().frame(height: 12)
            Text("Your name shows up in every alert the other person gets.")
                .font(.hs(16))
                .lineSpacing(3)
                .foregroundStyle(HS.text2)

            Spacer().frame(height: 28)

            TextField("Your name", text: $name)
                .font(.hs(19, .medium))
                .foregroundStyle(HS.text)
                .textContentType(.givenName)
                .autocorrectionDisabled()
                .focused($nameFocused)
                .padding(.horizontal, 18)
                .frame(height: 60)
                .background(HS.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(nameFocused ? HS.go : HS.line, lineWidth: nameFocused ? 1.5 : 1)
                )
                .onChange(of: name) { _, value in
                    if value.count > 30 { name = String(value.prefix(30)) }
                }
                .accessibilityLabel("Your name")

            Spacer().frame(height: 32)

            HSCard(padding: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    primer(
                        icon: "mappin.and.ellipse",
                        tint: HS.go,
                        title: "Location, only during a trip",
                        body: "Starts when you tap \"I'm coming\", stops the second you arrive. Never in the background otherwise."
                    )
                    Rectangle().fill(HS.line).frame(height: 1)
                    primer(
                        icon: "bell",
                        tint: HS.headstart,
                        title: "Notifications",
                        body: "Without these the walk-out alert can't reach you — it's the whole point."
                    )
                }
            }

            if let errorText {
                Spacer().frame(height: 16)
                Text(errorText).font(.hs(14)).foregroundStyle(HS.delayed)
            }

            Spacer()

            HSButton("Allow and continue", enabled: !trimmedName.isEmpty && !busy) {
                busy = true
                errorText = nil
                let value = trimmedName
                Task {
                    errorText = await onContinue(value)
                    busy = false
                }
            }
            .padding(.bottom, 38)
        }
        .onAppear { nameFocused = true }
    }

    private func primer(icon: String, tint: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(HS.raised)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.hs(16, .semibold)).foregroundStyle(HS.text)
                Text(body).font(.hs(14)).lineSpacing(3).foregroundStyle(HS.text2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Profile") {
    ProfileView(onBack: {}, onContinue: { _ in nil })
}

#Preview("Profile — filled") {
    ProfileView(name: "Mostafi", onBack: {}, onContinue: { _ in nil })
}
