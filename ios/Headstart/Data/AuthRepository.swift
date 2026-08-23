// ios/Headstart/Data/AuthRepository.swift
//
// Phone-OTP sign-in, and the one place the app holds a uid.
//
// WHY THIS IS TESTABLE AT ALL. Against real Firebase, phone auth verifies the app with a
// silent APNs push and falls back to a reCAPTCHA web view when that is impossible — which is
// exactly the case on a Simulator with no APNs key and no paid team. Against the Auth
// emulator (wired in AppDelegate, see BackendEnvironment) neither is needed: the emulator
// prints the code and serves it over REST at
//   GET http://127.0.0.1:9099/emulator/v1/projects/fin-e8358/verificationCodes
// provided the SDK is told not to attempt app verification. That is what
// `isAppVerificationDisabledForTesting` below does, and it is set ONLY when we are pointed at
// an emulator — never against real Firebase, where it would be a security hole.
// Canonical test numbers: +15555550100 (driver) / +15555550101 (receiver).
//
// Concurrency: @MainActor, like every repository. The auth state listener fires on an
// arbitrary queue, so it captures nothing but a plain `String?` and hops back with
// `Task { @MainActor in … }`. Capturing the `User` object itself would be a non-Sendable
// capture and Swift 6 rejects it.

import Foundation
import FirebaseAuth

@MainActor
public final class AuthRepository: ObservableObject {

    /// nil until the first `signIn` completes, and again after `signOut`.
    @Published public private(set) var uid: String?

    /// The E.164 number the code was sent to — the "Sent to …" line on Verify.
    @Published public private(set) var pendingNumber: String?

    /// The display name written at the end of onboarding. Kept here so `registerPushToken`
    /// (a later batch) can pass it without re-reading the Auth user.
    @Published public private(set) var displayName: String?

    private var verificationID: String?
    private var stateHandle: AuthStateDidChangeListenerHandle?

    public init() {
        let user = Auth.auth().currentUser
        uid = user?.uid
        displayName = user?.displayName
        configureForEmulatorIfNeeded()
        // Deliberately no `removeStateDidChangeListener` in `deinit`: this object is a
        // process-lifetime singleton held by `ServiceLocator`, and a nonisolated `deinit`
        // may not touch the non-Sendable handle under Swift 6. `stop()` exists for tests.
        stateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            let nextUid = user?.uid
            let nextName = user?.displayName
            Task { @MainActor in
                self?.uid = nextUid
                self?.displayName = nextName
            }
        }
    }

    public var isSignedIn: Bool { uid != nil }

    /// Only meaningful against the emulator. On real Firebase this stays false, so the SDK
    /// does its normal APNs / reCAPTCHA app verification.
    private func configureForEmulatorIfNeeded() {
        guard BackendEnvironment.emulatorHost != nil else { return }
        Auth.auth().settings?.isAppVerificationDisabledForTesting = true
        NSLog("[HS][auth] app verification disabled (emulator)")
    }

    /// Sends the six-digit code. `e164` must already be normalised by `PhoneNumber.e164`.
    public func sendCode(to e164: String) async throws {
        do {
            let id = try await PhoneAuthProvider.provider()
                .verifyPhoneNumber(e164, uiDelegate: nil)
            verificationID = id
            pendingNumber = e164
        } catch {
            throw Self.mapAuthError(error)
        }
    }

    /// Re-sends to the number the last `sendCode` used. No-op when there is none.
    public func resendCode() async throws {
        guard let pendingNumber else { return }
        try await sendCode(to: pendingNumber)
    }

    /// Exchanges the code for a session. Throws `.badCode` when the code is wrong.
    public func verify(code: String) async throws {
        guard let verificationID else { throw HeadstartError.badCode }
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: code
        )
        do {
            let result = try await Auth.auth().signIn(with: credential)
            uid = result.user.uid
            displayName = result.user.displayName
        } catch {
            throw Self.mapAuthError(error)
        }
    }

    /// The profile step. Written to the Auth user so it survives reinstall-free relaunches;
    /// the copy that the OTHER person reads is `pairs/{id}.memberNames`, which the backend
    /// denormalises from `registerPushToken({displayName})` (ADDENDUM §M).
    public func setDisplayName(_ name: String) async throws {
        guard let user = Auth.auth().currentUser else { throw HeadstartError.unauthenticated }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HeadstartError.badName }
        let request = user.createProfileChangeRequest()
        request.displayName = trimmed
        do {
            try await request.commitChanges()
            displayName = trimmed
        } catch {
            throw Self.mapAuthError(error)
        }
    }

    public func signOut() throws {
        do {
            try Auth.auth().signOut()
        } catch {
            throw Self.mapAuthError(error)
        }
        verificationID = nil
        pendingNumber = nil
        displayName = nil
        uid = nil
    }

    /// Detaches the state listener. Only tests need this — the app never tears the
    /// repository down.
    public func stop() {
        if let stateHandle {
            Auth.auth().removeStateDidChangeListener(stateHandle)
            self.stateHandle = nil
        }
    }

    // MARK: -

    /// `AuthErrorDomain` codes are not the callable error codes `HeadstartError` maps, so the
    /// two that a person can actually cause are translated by hand and everything else falls
    /// through to the shared mapper.
    private static func mapAuthError(_ error: Error) -> HeadstartError {
        let ns = error as NSError
        guard ns.domain == AuthErrorDomain else { return error.asHeadstartError() }
        switch ns.code {
        case AuthErrorCode.invalidVerificationCode.rawValue,
             AuthErrorCode.missingVerificationCode.rawValue,
             AuthErrorCode.sessionExpired.rawValue:
            return .badCode
        case AuthErrorCode.invalidPhoneNumber.rawValue,
             AuthErrorCode.missingPhoneNumber.rawValue:
            return .unknown("invalid-phone-number")
        case AuthErrorCode.tooManyRequests.rawValue,
             AuthErrorCode.quotaExceeded.rawValue:
            return .rateLimited
        case AuthErrorCode.networkError.rawValue:
            return .offline
        case AuthErrorCode.userTokenExpired.rawValue,
             AuthErrorCode.invalidUserToken.rawValue,
             AuthErrorCode.userNotFound.rawValue:
            return .unauthenticated
        default:
            return error.asHeadstartError()
        }
    }
}
