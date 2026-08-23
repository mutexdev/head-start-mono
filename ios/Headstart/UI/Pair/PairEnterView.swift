// ios/Headstart/UI/Pair/PairEnterView.swift
import SwiftUI

/// `design/PairEnter.dc.html`, minus the "Scan their QR instead" row (M4).
///
/// The field can only ever hold characters from the server's alphabet — that filtering is
/// `PhoneNumber.sanitizeInviteCode`, which also lets someone paste the whole share sentence
/// from `PairInviteView` and still land the six characters that matter.
///
/// The two errors this screen must be able to say out loud are `bad-code` and `own-code`
/// (CLIENT_CONTRACT.md line 13); the caller passes back `HeadstartError.userMessage`.
public struct PairEnterView: View {

    @State private var code: String
    @State private var busy = false
    @State private var errorText: String?

    private let onBack: () -> Void
    private let onPair: (String) async -> String?

    /// - Parameters:
    ///   - code: prefilled from a `headstart://pair/{code}` deep link, when there was one.
    ///   - onPair: returns an error message, or nil on success.
    public init(
        code: String = "",
        onBack: @escaping () -> Void,
        onPair: @escaping (String) async -> String?
    ) {
        _code = State(initialValue: PhoneNumber.sanitizeInviteCode(code))
        self.onBack = onBack
        self.onPair = onPair
    }

    public var body: some View {
        HSScreen {
            Spacer().frame(height: 26)
            HSBackBar(action: onBack)
            Spacer().frame(height: 26)

            Text("Enter their code")
                .font(.hs(30, .bold))
                .tracking(-1)
                .foregroundStyle(HS.text)
            Spacer().frame(height: 12)
            Text("Six characters, from the invite they sent you.")
                .font(.hs(16))
                .lineSpacing(3)
                .foregroundStyle(HS.text2)

            Spacer().frame(height: 36)

            HSCodeField(
                text: $code,
                boxHeight: 62,
                fontSize: 24,
                keyboard: .asciiCapable,
                contentType: nil,
                sanitize: PhoneNumber.sanitizeInviteCode
            )

            if let errorText {
                Spacer().frame(height: 20)
                Text(errorText)
                    .font(.hs(14))
                    .foregroundStyle(HS.delayed)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Spacer()

            HSButton("Pair", enabled: PhoneNumber.isCompleteInviteCode(code) && !busy) {
                busy = true
                errorText = nil
                Task {
                    errorText = await onPair(code)
                    busy = false
                }
            }
            .padding(.bottom, 38)
        }
    }
}

#Preview("Pair — enter") {
    PairEnterView(onBack: {}, onPair: { _ in nil })
}

#Preview("Pair — bad code") {
    PairEnterView(code: "K7M2QP", onBack: {}, onPair: { _ in HeadstartError.badCode.userMessage })
}

#Preview("Pair — own code") {
    PairEnterView(code: "K7M2QP", onBack: {}, onPair: { _ in HeadstartError.ownCode.userMessage })
}
