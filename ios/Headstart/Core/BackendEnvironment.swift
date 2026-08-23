// ios/Headstart/Core/BackendEnvironment.swift
//
// ─────────────────────────────────────────────────────────────────────────────
// CONCURRENCY LAW FOR THIS TARGET — read before adding any file.
//
// 1. Swift 6 language mode is ON project-wide (SWIFT_VERSION = 6.0).
// 2. Do NOT blanket-add `@preconcurrency import` to Firebase files. The plan
//    doc's rule ("every file that touches Firebase uses @preconcurrency import")
//    described Firebase 11.x and is FALSE of 12.18.0: a Firestore
//    snapshot-listener-to-AsyncStream bridge, an async httpsCallable(...).call,
//    a @MainActor CLLocationManagerDelegate, and an Auth.addStateDidChangeListener
//    closure all compile with zero concurrency warnings and no @preconcurrency.
//    Add it to a single import only if that specific file actually errors —
//    clean imports keep the real Sendable diagnostics visible.
// 3. All repositories, LocationTracker, AppViewModel and ServiceLocator are
//    @MainActor.
// 4. Firestore / Functions / Auth callbacks hop back with `Task { @MainActor in … }`.
// 5. CLLocationManagerDelegate methods are `nonisolated` and use
//    `MainActor.assumeIsolated { … }`.
// 6. Every model, DTO and pure-logic type is a `Sendable` value type.
// 7. The only escape hatch is a `final class ListenerBox: @unchecked Sendable`
//    holding a ListenerRegistration, removed in `onTermination`.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

/// Where the app's Firebase traffic goes: the Local Emulator Suite, or real cloud.
///
/// The plan assumes deployed Cloud Functions and real Firebase throughout, which
/// is exactly what is unavailable in M1 (no Blaze billing, no APNs key, no SMS).
/// The Firebase Local Emulator Suite is the sanctioned verification path, so the
/// app needs a switch. Resolution order, highest precedence first:
///
///   1. `HSUseEmulator` UserDefaults bool — explicitly `NO` forces real cloud.
///      `xcrun simctl launch <udid> com.mutexdev.headstart -HSUseEmulator NO`
///   2. `HS_EMULATOR_HOST` environment variable (scheme / CI).
///   3. `HSEmulatorHost` UserDefaults string — `-HSEmulatorHost 10.0.0.5` retargets.
///   4. `#if HS_EMULATOR` compile flag — set on Debug only, so Debug defaults to
///      the emulator and Release defaults to real Firebase.
///
/// Ports are fixed by the emulator contract (docs/CLIENT_CONTRACT_ADDENDUM.md):
/// auth 9099, firestore 8080, functions 5001. From the iOS Simulator the host is
/// `127.0.0.1` (the AVD's `10.0.2.2` is Android's problem, not ours).
enum BackendEnvironment {
    static let authPort = 9099, firestorePort = 8080, functionsPort = 5001

    /// nil == talk to real Firebase.
    static var emulatorHost: String? {
        let d = UserDefaults.standard
        if d.object(forKey: "HSUseEmulator") != nil, d.bool(forKey: "HSUseEmulator") == false { return nil }
        if let h = ProcessInfo.processInfo.environment["HS_EMULATOR_HOST"], !h.isEmpty { return h }
        if let h = d.string(forKey: "HSEmulatorHost"), !h.isEmpty { return h }
        #if HS_EMULATOR
        return "127.0.0.1"
        #else
        return nil
        #endif
    }
}
