// ios/Headstart/UI/Onboarding/PhoneView.swift
import SwiftUI

/// `design/Phone.dc.html`. Stateless apart from what the two fields hold: the caller does the
/// sending and hands back an error message to show, or nil.
public struct PhoneView: View {

    @State private var dialCode: String
    @State private var national: String
    @State private var busy = false
    @State private var errorText: String?
    @FocusState private var numberFocused: Bool

    private let onBack: () -> Void
    private let onSend: (String) async -> String?

    /// - Parameters:
    ///   - onSend: receives the assembled E.164 number; returns an error message to show
    ///     under the field, or nil when the code went out.
    public init(
        dialCode: String = "+880",
        national: String = "",
        onBack: @escaping () -> Void,
        onSend: @escaping (String) async -> String?
    ) {
        _dialCode = State(initialValue: dialCode)
        _national = State(initialValue: national)
        self.onBack = onBack
        self.onSend = onSend
    }

    private var e164: String? { PhoneNumber.e164(dialCode: dialCode, national: national) }

    public var body: some View {
        HSScreen {
            Spacer().frame(height: 26)
            HSBackBar(action: onBack)
            Spacer().frame(height: 28)

            Text("What's your number?")
                .font(.hs(30, .bold))
                .tracking(-1)
                .foregroundStyle(HS.text)
            Spacer().frame(height: 12)
            Text("We'll text you a six-digit code. No password to remember, no email.")
                .font(.hs(16))
                .lineSpacing(3)
                .foregroundStyle(HS.text2)

            Spacer().frame(height: 36)

            HStack(spacing: 10) {
                TextField("+880", text: $dialCode)
                    .font(.hs(18, .medium))
                    .foregroundStyle(HS.text)
                    .multilineTextAlignment(.center)
                    .keyboardType(.phonePad)
                    .frame(width: 104, height: 60)
                    .background(HS.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(HS.line, lineWidth: 1)
                    )
                    .accessibilityLabel("Country dialling code")

                TextField("1712 345678", text: $national)
                    .font(.hsNum(20, .medium))
                    .foregroundStyle(HS.text)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .focused($numberFocused)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(HS.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                numberFocused ? HS.go : HS.line,
                                lineWidth: numberFocused ? 1.5 : 1
                            )
                    )
                    .accessibilityLabel("Phone number")
            }

            Spacer().frame(height: 20)
            HSPrivacyFooter(
                "Your number is only ever shown to the one person you pair with.",
                centered: false
            )

            if let errorText {
                Spacer().frame(height: 16)
                Text(errorText).font(.hs(14)).foregroundStyle(HS.delayed)
            }

            Spacer()

            HSButton("Send code", enabled: e164 != nil && !busy) {
                guard let number = e164 else { return }
                busy = true
                errorText = nil
                Task {
                    errorText = await onSend(number)
                    busy = false
                }
            }
            .padding(.bottom, 38)
        }
        .onAppear { numberFocused = true }
    }
}

#Preview("Phone") {
    PhoneView(national: "1712345678", onBack: {}, onSend: { _ in nil })
}

#Preview("Phone — error") {
    PhoneView(national: "1712345678", onBack: {}, onSend: { _ in
        HeadstartError.rateLimited.userMessage
    })
}
