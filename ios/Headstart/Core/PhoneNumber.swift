// ios/Headstart/Core/PhoneNumber.swift
//
// Input sanitising for the three code-ish fields in the app: the phone number, the six-digit
// SMS code, and the six-character invite code. Deliberately NOT a libphonenumber port —
// Firebase validates the number server-side and returns `invalid-phone-number`, so all we owe
// the person typing is to not send obvious junk and to not let them type a character the
// server can never accept.
//
// Pure Foundation, so it is table-tested with no Firebase linkage (`PhoneNumberTests`).

import Foundation

public enum PhoneNumber {

    /// CLIENT_CONTRACT.md line 12 — the server mints invite codes from exactly this
    /// alphabet: no I, no O, no 0, no 1, because those four are what people mistype when
    /// they read a code off another phone's screen. The client only ever DISPLAYS a code
    /// the server minted and ACCEPTS one a person types; it never generates one.
    public static let inviteAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    public static let inviteCodeLength = 6
    public static let otpLength = 6

    private static let inviteAlphabetSet = Set(inviteAlphabet)

    /// "+880" + "01712 345678" -> "+8801712345678", or nil when it cannot be a number.
    ///
    /// The national trunk zero is stripped: people in Bangladesh, the UK and most of Europe
    /// write their number with a leading 0 that must not appear in E.164.
    public static func e164(dialCode: String, national: String) -> String? {
        let code = dialCode.filter(\.isNumber)
        guard !code.isEmpty else { return nil }
        var digits = national.filter(\.isNumber)
        while digits.hasPrefix("0") { digits.removeFirst() }
        guard digits.count >= 6, digits.count <= 14 else { return nil }
        return "+" + code + digits
    }

    /// Digits only, at most six — the SMS code field.
    public static func sanitizeOtp(_ raw: String) -> String {
        String(raw.filter(\.isNumber).prefix(otpLength))
    }

    /// Uppercase, server alphabet only, at most six — the invite code field. Pasting
    /// "k7-m2 qp" or a whole share sentence still lands the six characters that matter.
    public static func sanitizeInviteCode(_ raw: String) -> String {
        String(raw.uppercased().filter { inviteAlphabetSet.contains($0) }.prefix(inviteCodeLength))
    }

    /// True when the field holds a complete, well-formed invite code.
    public static func isCompleteInviteCode(_ raw: String) -> Bool {
        sanitizeInviteCode(raw).count == inviteCodeLength
    }
}
