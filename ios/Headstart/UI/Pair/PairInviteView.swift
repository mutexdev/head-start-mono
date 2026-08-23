// ios/Headstart/UI/Pair/PairInviteView.swift
import SwiftUI

/// `design/PairInvite.dc.html`, minus the QR square — QR and NFC pairing are M4 (spec §11),
/// and drawing an unscannable square would be a lie. The code, a share sheet and a copy
/// button are the whole screen.
///
/// The share text is fixed by ADDENDUM §N: `headstart://` is the only scheme, and the sentence
/// leads with the bare code so manual entry works even when the link does not resolve (the
/// other person may not have installed the app yet).
public struct PairInviteView: View {

    private let code: String?
    private let errorText: String?
    private let onBack: () -> Void
    private let onRetry: () -> Void

    @State private var copied = false

    public init(
        code: String?,
        errorText: String? = nil,
        onBack: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) {
        self.code = code
        self.errorText = errorText
        self.onBack = onBack
        self.onRetry = onRetry
    }

    /// ADDENDUM §N. Both platforms send this sentence, in this order.
    static func shareText(for code: String) -> String {
        "Pair with me on Headstart. Code: \(code) — headstart://pair/\(code)"
    }

    public var body: some View {
        HSScreen {
            Spacer().frame(height: 26)
            HSBackBar(action: onBack)
            Spacer().frame(height: 20)

            Text("Your invite")
                .font(.hs(30, .bold))
                .tracking(-1)
                .foregroundStyle(HS.text)
            Spacer().frame(height: 10)
            Text("They enter this code in their app. It works once, and only for them.")
                .font(.hs(16))
                .lineSpacing(3)
                .foregroundStyle(HS.text2)

            Spacer().frame(height: 28)

            HSCard(padding: 26, radius: 18) {
                VStack(spacing: 22) {
                    if let code {
                        Text(code)
                            .font(.hsNum(44, .bold))
                            .tracking(8)
                            .padding(.leading, 8)   // optical: tracking adds space after the last glyph
                            .foregroundStyle(HS.text)
                            .accessibilityLabel("Invite code")
                            .accessibilityValue(code.map(String.init).joined(separator: " "))
                    } else if errorText == nil {
                        ProgressView().tint(HS.text2).frame(height: 52)
                    } else {
                        Text("—").font(.hsNum(44, .bold)).foregroundStyle(HS.text3)
                    }
                    Rectangle().fill(HS.line).frame(height: 1)
                    Text("Expires in 24 hours")
                        .font(.hs(14))
                        .foregroundStyle(HS.text3)
                }
                .frame(maxWidth: .infinity)
            }

            if let errorText {
                Spacer().frame(height: 16)
                Text(errorText).font(.hs(14)).foregroundStyle(HS.delayed)
                Spacer().frame(height: 12)
                HSButton("Try again", kind: .secondary, action: onRetry)
            }

            Spacer()

            VStack(spacing: 12) {
                if let code {
                    ShareLink(item: Self.shareText(for: code)) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Share link").font(.hs(17, .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: HS.controlHeight)
                        .foregroundStyle(HS.goInk)
                        .background(HS.go)
                        .clipShape(RoundedRectangle(cornerRadius: HS.Radius.control, style: .continuous))
                    }

                    HSButton(copied ? "Copied" : "Copy code", kind: .secondary) {
                        UIPasteboard.general.string = code
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    }
                }
            }
            .padding(.bottom, 38)
        }
    }
}

#Preview("Pair — invite") {
    PairInviteView(code: "K7M2QP", onBack: {}, onRetry: {})
}

#Preview("Pair — invite loading") {
    PairInviteView(code: nil, onBack: {}, onRetry: {})
}

#Preview("Pair — invite failed") {
    PairInviteView(
        code: nil,
        errorText: HeadstartError.offline.userMessage,
        onBack: {},
        onRetry: {}
    )
}
