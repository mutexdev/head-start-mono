// ios/Headstart/UI/CodeField.swift
import SwiftUI

/// Six boxes with one invisible text field behind them — the pattern on `Verify.dc.html`
/// (digits, 64 pt boxes) and `PairEnter.dc.html` (letters and digits, 62 pt boxes). The caret
/// is drawn by us, because a real caret cannot be positioned per box.
///
/// The `sanitize` closure is the ONLY thing that decides what a box may contain, so the two
/// call sites hand it `PhoneNumber.sanitizeOtp` and `PhoneNumber.sanitizeInviteCode` and the
/// field itself stays ignorant of alphabets and lengths.
public struct HSCodeField: View {

    @Binding private var text: String
    private let length: Int
    private let boxHeight: CGFloat
    private let fontSize: CGFloat
    private let keyboard: UIKeyboardType
    private let contentType: UITextContentType?
    private let sanitize: (String) -> String

    @FocusState private var focused: Bool

    public init(
        text: Binding<String>,
        length: Int = 6,
        boxHeight: CGFloat = 64,
        fontSize: CGFloat = 26,
        keyboard: UIKeyboardType = .numberPad,
        contentType: UITextContentType? = .oneTimeCode,
        sanitize: @escaping (String) -> String
    ) {
        self._text = text
        self.length = length
        self.boxHeight = boxHeight
        self.fontSize = fontSize
        self.keyboard = keyboard
        self.contentType = contentType
        self.sanitize = sanitize
    }

    public var body: some View {
        ZStack {
            TextField("", text: $text)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($focused)
                // Not `.hidden()` and not zero-opacity: a fully transparent field still
                // takes the keyboard, but a hidden one is removed from the hierarchy.
                .opacity(0.001)
                .onChange(of: text) { _, newValue in
                    let clean = sanitize(newValue)
                    if clean != newValue { text = clean }
                }

            HStack(spacing: 9) {
                ForEach(0..<length, id: \.self) { index in
                    box(at: index)
                }
            }
            .allowsHitTesting(false)
        }
        // The whole row is the tap target, so no individual box is under 44 pt of reachable
        // area even though each is only ~48 pt wide.
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { focused = true }
        .accessibilityElement()
        .accessibilityLabel("Code")
        .accessibilityValue(text.isEmpty ? "Empty" : text.map(String.init).joined(separator: " "))
    }

    private func box(at index: Int) -> some View {
        let characters = Array(text)
        let isCursor = focused && index == characters.count && index < length
        return ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(HS.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(isCursor ? HS.go : HS.line, lineWidth: isCursor ? 1.5 : 1)
                )
            if index < characters.count {
                Text(String(characters[index]))
                    .font(.hsNum(fontSize, .semibold))
                    .foregroundStyle(HS.text)
            } else if isCursor {
                Rectangle()
                    .fill(HS.go)
                    .frame(width: 2, height: fontSize + 2)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: boxHeight)
    }
}

#Preview("Code field") {
    struct Harness: View {
        @State private var otp = "492"
        @State private var invite = "K7M2QP"
        var body: some View {
            HSScreen {
                Spacer().frame(height: 60)
                HSSectionLabel("SMS code")
                Spacer().frame(height: 12)
                HSCodeField(text: $otp, sanitize: PhoneNumber.sanitizeOtp)
                Spacer().frame(height: 40)
                HSSectionLabel("Invite code")
                Spacer().frame(height: 12)
                HSCodeField(
                    text: $invite,
                    boxHeight: 62,
                    fontSize: 24,
                    keyboard: .asciiCapable,
                    contentType: nil,
                    sanitize: PhoneNumber.sanitizeInviteCode
                )
                Spacer()
            }
        }
    }
    return Harness()
}
