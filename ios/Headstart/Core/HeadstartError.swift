// ios/Headstart/Core/HeadstartError.swift
import Foundation

// NOTE: the plan doc pulls in the FirebaseFunctions module here, purely to reach
// `FunctionsErrorDomain` and `FunctionsErrorCode`. Both are constants — the domain string
// and the gRPC status numbers — so they are declared below instead and this file stays
// Foundation-only, which keeps the mapper unit-testable with no Firebase linkage and
// satisfies the batch rule that nothing under Core/ depends on the Firebase SDK.

/// `FunctionsErrorDomain` from the Firebase Functions SDK.
public let kFunctionsErrorDomain = "com.firebase.functions"

/// The gRPC status codes `FunctionsErrorCode` is built from. Only the transport-level
/// facts that outrank the callable's message are needed here.
public enum CallableStatus {
    public static let deadlineExceeded = 4
    public static let unavailable = 14
    public static let unauthenticated = 16
}

/// Every failure the UI has to explain. `code` is the wire value from CLIENT_CONTRACT.md;
/// `userMessage` is what a screen may put in front of a person.
public enum HeadstartError: Error, Equatable, Sendable {
    case notPaired
    case tripActive
    case spotNotFound
    case badCode
    case ownCode
    case driverOnly
    case tripNotFound
    case badCoords
    case badName
    case badToken
    /// CLIENT_CONTRACT_ADDENDUM.md §O — `sendReply` with empty custom text.
    case badReply
    /// Spec §9 mentions rate limiting; not in the contract's exhaustive ten, but mapped.
    case rateLimited
    case unauthenticated
    case offline
    case unknown(String)

    public var code: String {
        switch self {
        case .notPaired: return "not-paired"
        case .tripActive: return "trip-active"
        case .spotNotFound: return "spot-not-found"
        case .badCode: return "bad-code"
        case .ownCode: return "own-code"
        case .driverOnly: return "driver-only"
        case .tripNotFound: return "trip-not-found"
        case .badCoords: return "bad-coords"
        case .badName: return "bad-name"
        case .badToken: return "bad-token"
        case .badReply: return "bad-reply"
        case .rateLimited: return "rate-limited"
        case .unauthenticated: return "unauthenticated"
        case .offline: return "offline"
        case .unknown(let raw): return raw
        }
    }

    public var userMessage: String {
        switch self {
        case .notPaired: return "You're not paired with anyone yet."
        case .tripActive: return "A trip is already running."
        case .spotNotFound: return "That pickup spot no longer exists."
        case .badCode: return "That code isn't valid. Check the six characters and try again."
        case .ownCode: return "That's your own invite code. Send it to the other person."
        case .driverOnly: return "Only the driver can do that."
        case .tripNotFound: return "That trip has already ended."
        case .badCoords: return "We couldn't read that location. Try again."
        case .badName: return "Give the spot a name of 1 to 40 characters."
        case .badToken: return "Notifications aren't set up on this phone yet."
        case .badReply: return "Write something before you send it."
        case .rateLimited: return "Too many tries. Wait a moment, then try again."
        case .unauthenticated: return "Sign in again to continue."
        case .offline: return "No connection. We'll try again when you're back online."
        case .unknown: return "Something went wrong. Try again."
        }
    }
}

/// Longest code first, so a `contains` match never returns a prefix of a longer code.
private let byCode: [HeadstartError] = [
    .notPaired, .tripActive, .spotNotFound, .badCode, .ownCode,
    .driverOnly, .tripNotFound, .badCoords, .badName, .badToken,
    .badReply, .rateLimited,
]

/// Pure mapper: callable message (plus two transport facts) to a typed error.
/// Auth and connectivity outrank the message, because a stale token can produce any message.
public func headstartErrorFor(
    _ message: String?,
    isNetwork: Bool = false,
    isUnauthenticated: Bool = false
) -> HeadstartError {
    if isUnauthenticated { return .unauthenticated }
    if isNetwork { return .offline }
    let text = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return .unknown("unknown") }
    if let exact = byCode.first(where: { $0.code == text }) { return exact }
    // Some transports prefix the status, e.g. "INVALID_ARGUMENT: bad-code".
    if let contained = byCode.first(where: { text.contains($0.code) }) { return contained }
    return .unknown(text)
}

public extension Error {
    /// Adapter from whatever the Firebase SDK threw.
    func asHeadstartError() -> HeadstartError {
        if let already = self as? HeadstartError { return already }
        let ns = self as NSError
        var isUnauthenticated = false
        var isNetwork = ns.domain == NSURLErrorDomain
        if ns.domain == kFunctionsErrorDomain {
            isUnauthenticated = ns.code == CallableStatus.unauthenticated
            isNetwork = isNetwork
                || ns.code == CallableStatus.unavailable
                || ns.code == CallableStatus.deadlineExceeded
        }
        let message = (ns.userInfo[NSLocalizedDescriptionKey] as? String) ?? ns.localizedDescription
        return headstartErrorFor(message, isNetwork: isNetwork, isUnauthenticated: isUnauthenticated)
    }
}
