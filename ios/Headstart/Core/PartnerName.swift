// ios/Headstart/Core/PartnerName.swift
//
// Almost every artboard names the other person — "Sara walks out 3 min early", "Sharing
// with Sara", "Mostafi is driving".
//
// This implements the AMENDMENT at the top of the iOS plan doc, NOT Task 10's original
// body. Task 10 was written before the backend denormalised both display names onto the
// pair document, and it recovered the name by parsing push titles. That workaround is dead:
// the backend now writes `pairs/{pairId}.memberNames` (a `uid -> displayName` map either
// member may read), so the name is a plain dictionary lookup — CLIENT_CONTRACT.md line 31
// and CLIENT_CONTRACT_ADDENDUM.md §M. Neither side ever reads the other's user document;
// the rules would deny it anyway.
//
// Both platforms must resolve the name IDENTICALLY, so the rule is written out here in
// full and Android must match it exactly:
//
//   1. take `memberNames[otherUid]`
//   2. trim surrounding whitespace and newlines
//   3. if what is left is empty — or the key is missing, or `otherUid` is unknown because
//      the pair is still pending — the name is the fallback "Your partner"
//
// There is no truncation and no capitalisation fixing: the name is whatever the person
// typed on the profile screen, and the server already bounds its length.

import Foundation

public enum PartnerName {

    /// Shown wherever the map has no name for the partner yet — a pending pair, or a
    /// member who has not finished the profile step. Sentence-initial by design, because
    /// every artboard that can show it starts a sentence with it.
    public static let fallback = "Your partner"

    /// Mid-sentence stand-in for tight layouts, e.g. "…so they know you're coming".
    public static let shortFallback = "they"

    /// The canonical resolution. `otherUid == nil` means the pair has no second member yet.
    public static func resolve(memberNames: [String: String]?, otherUid: String?) -> String {
        clean(rawName(memberNames: memberNames, otherUid: otherUid)) ?? fallback
    }

    /// Convenience over the pair document: resolves the name of whoever is not `selfUid`.
    public static func resolve(pair: Pair?, selfUid: String) -> String {
        guard let pair else { return fallback }
        return resolve(memberNames: pair.memberNames, otherUid: pair.other(than: selfUid))
    }

    /// Mid-sentence form: the name, or "they".
    public static func short(memberNames: [String: String]?, otherUid: String?) -> String {
        clean(rawName(memberNames: memberNames, otherUid: otherUid)) ?? shortFallback
    }

    public static func short(pair: Pair?, selfUid: String) -> String {
        guard let pair else { return shortFallback }
        return short(memberNames: pair.memberNames, otherUid: pair.other(than: selfUid))
    }

    /// True when a real name was found — for the few places that want to say
    /// "Sharing with Sara" only if there is a Sara.
    public static func isKnown(memberNames: [String: String]?, otherUid: String?) -> Bool {
        clean(rawName(memberNames: memberNames, otherUid: otherUid)) != nil
    }

    // MARK: -

    private static func rawName(memberNames: [String: String]?, otherUid: String?) -> String? {
        guard let memberNames, let otherUid, !otherUid.isEmpty else { return nil }
        return memberNames[otherUid]
    }

    private static func clean(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
