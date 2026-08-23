// ios/Headstart/UI/Onboarding/VerifyView.swift
import SwiftUI

/// `design/Verify.dc.html`.
///
/// The resend countdown is a plain `Task` loop rather than a timer publisher: this codebase
/// has exactly one streaming primitive (`AsyncStream`, decision D8) and no reactive-framework
/// types anywhere, and a one-second countdown is not a reason to make an exception.
public struct VerifyView: View {

    @State private var code = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var secondsLeft: Int
    /// Bumped to restart the countdown task after a resend.
    @State private var countdownRun = 0

    private let displayNumber: String
    private let resendSeconds: Int
    private let onBack: () -> Void
    private let onVerify: (String) async -> String?
    private let onResend: () async -> Void

    public init(
        displayNumber: String,
        resendSeconds: Int = 30,
        onBack: @escaping () -> Void,
        onVerify: @escaping (String) async -> String?,
        onResend: @escaping () async -> Void
    ) {
        self.displayNumber = displayNumber
        self.resendSeconds = resendSeconds
        _secondsLeft = State(initialValue: resendSeconds)
        self.onBack = onBack
        self.onVerify = onVerify
        self.onResend = onResend
    }

    public var body: some View {
        HSScreen {
            Spacer().frame(height: 26)
            HSBackBar(action: onBack)
            Spacer().frame(height: 28)

            Text("Enter the code")
                .font(.hs(30, .bold))
                .tracking(-1)
                .foregroundStyle(HS.text)
            Spacer().frame(height: 12)
            HStack(spacing: 5) {
                Text("Sent to \(displayNumber).").font(.hs(16)).foregroundStyle(HS.text2)
                Button("Change number", action: onBack)
                    .font(.hs(16))
                    .foregroundStyle(HS.go)
                    .buttonStyle(.plain)
            }

            Spacer().frame(height: 40)

            HSCodeField(text: $code, keyboard: .numberPad, sanitize: PhoneNumber.sanitizeOtp)

            Spacer().frame(height: 24)

            resendRow

            if let errorText {
                Spacer().frame(height: 12)
                Text(errorText)
                    .font(.hs(14))
                    .foregroundStyle(HS.delayed)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Spacer()

            HSButton("Verify", enabled: code.count == PhoneNumber.otpLength && !busy) {
                busy = true
                errorText = nil
                Task {
                    errorText = await onVerify(code)
                    busy = false
                }
            }
            .padding(.bottom, 38)
        }
        .task(id: countdownRun) {
            secondsLeft = resendSeconds
            while secondsLeft > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                secondsLeft -= 1
            }
        }
    }

    private var resendRow: some View {
        Group {
            if secondsLeft > 0 {
                Text("Resend in ").foregroundStyle(HS.text3)
                    + Text(formatCountdown(secondsLeft)).foregroundStyle(HS.text2)
            } else {
                Text("Resend code").foregroundStyle(HS.go)
            }
        }
        .font(.hsNum(15, .regular))
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: HS.minTouchTarget)
        .contentShape(Rectangle())
        .onTapGesture {
            guard secondsLeft == 0 else { return }
            countdownRun += 1
            Task { await onResend() }
        }
    }
}

#Preview("Verify") {
    VerifyView(
        displayNumber: "+880 1712 345678",
        onBack: {},
        onVerify: { _ in nil },
        onResend: {}
    )
}

#Preview("Verify — wrong code, resend ready") {
    VerifyView(
        displayNumber: "+1 555 555 0100",
        resendSeconds: 0,
        onBack: {},
        onVerify: { _ in HeadstartError.badCode.userMessage },
        onResend: {}
    )
}
