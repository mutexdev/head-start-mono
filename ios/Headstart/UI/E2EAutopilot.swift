// ios/Headstart/UI/E2EAutopilot.swift
//
// DEBUG-ONLY, EMULATOR-ONLY TEST HARNESS. Absent from Release entirely.
//
// WHY THIS EXISTS — read before deleting it as "test code in the app".
//
// The milestone gate for M1 is a real drive on two phones. There are no phones, no paid
// Apple team, no APNs key and no SMS here, so the sanctioned substitute is the Firebase
// Local Emulator Suite plus the iOS Simulator (docs/CLIENT_CONTRACT_ADDENDUM.md,
// "Emulator contract"). That leaves exactly one gap: **`xcrun simctl` cannot tap.** It can
// boot, install, grant privacy, push a notification, move the device and read the log
// stream — there is no subcommand that touches the screen. So a headless drive can drive
// the WORLD around the app but cannot drive the app itself.
//
// The two ways out are an XCUITest target (a second scheme, custom SwiftUI controls with
// no accessibility identifiers, a code field that fights the software keyboard) or this:
// a launch-argument-driven autopilot that calls the SAME `AppViewModel` methods the
// buttons call. Nothing here reimplements product logic — every step below is one call
// into the view model, so a bug in sign-in, pairing, spot creation or `startTrip` fails
// the drive exactly as a human tap would.
//
// It is inert unless BOTH are true:
//   * the app is pointed at an emulator (`BackendEnvironment.emulatorHost != nil`), and
//   * `-HSAutoSignIn <e164>` was passed on the command line.
// A Release build does not contain this file at all.
//
// Launch arguments (all `UserDefaults`, i.e. `xcrun simctl launch … -Key value`):
//
//   -HSAutoSignIn   +15555550100   phone number to sign in as; the OTP is read from the
//                                  Auth emulator's REST endpoint, exactly as the plan's
//                                  e2e step describes
//   -HSAutoName     Driver         display name for the profile step
//   -HSAutoPair     invite         `invite` = call createPair and log the code for the
//                                  harness to accept; `wait` = just wait to be paired
//   -HSAutoSpot     23.7806,90.4193  create this spot if the pair has none
//   -HSAutoSpotName Home
//   -HSAutoStartTrip YES           tap "I'm coming" on the primary spot once paired
//
// Every step logs `[HS][e2e] …`, which is what `ios/scripts/e2e-drive.sh` asserts on.

#if DEBUG
import Foundation
import FirebaseAuth
import FirebaseCore

@MainActor
enum E2EAutopilot {

    private static var hasRun = false

    static func runIfRequested(model: AppViewModel) async {
        guard !hasRun else { return }
        let defaults = UserDefaults.standard
        guard let host = BackendEnvironment.emulatorHost else { return }
        guard let number = defaults.string(forKey: "HSAutoSignIn"), !number.isEmpty else { return }
        hasRun = true
        NSLog("[HS][e2e] autopilot starting for \(number)")

        // A previous phase of the drive may have left a DIFFERENT identity signed in —
        // FirebaseAuth persists it in the keychain across launches, which is exactly what
        // we want in the product and exactly wrong when the harness is switching sides.
        if let current = Auth.auth().currentUser, current.phoneNumber != number {
            NSLog("[HS][e2e] signing out \(current.phoneNumber ?? "-") to sign in as \(number)")
            model.signOut()
            _ = await waitUntil(timeout: 20, "signedOut", { model.stage == .signedOut })
        }

        // 1. Phone OTP, with the code read straight out of the Auth emulator.
        if model.stage == .signedOut {
            if let error = await signIn(model: model, number: number, host: host) {
                NSLog("[HS][e2e] FAILED sign-in: \(error)")
                return
            }
        }
        NSLog("[HS][e2e] step=signedIn uid=\(model.uid ?? "-")")

        // 2. Profile — this is also the ONLY place the two permission prompts happen.
        //
        // NOT awaited, on purpose. `completeProfile` asks for notification permission, and
        // the notification prompt CANNOT BE ANSWERED HEADLESSLY: `xcrun simctl privacy` in
        // Xcode 26.6 has no `notifications` service (it lists calendar, contacts, location,
        // location-always, photos, media-library, microphone, motion, reminders, siri and
        // nothing else — `grant notifications` fails with "Operation not permitted"). The
        // system alert therefore sits on screen unanswered and the `await` never returns.
        //
        // So the harness starts the real product method and moves on as soon as the name is
        // saved, which is the step before the prompt. Everything this drive asserts works
        // without notification permission: `xcrun simctl push` payloads carry
        // `content-available: 1` and reach `application(_:didReceiveRemoteNotification:…)`
        // regardless, and that funnels into the same `PushRouter.handle(userInfo:)`.
        if model.stage == .needsProfile {
            let name = defaults.string(forKey: "HSAutoName") ?? "Tester"
            let profile = Task { await model.completeProfile(name: name) }
            defer { _ = profile }
            guard await waitUntil(timeout: 30, "profile", { !model.displayName.isEmpty }) else {
                NSLog("[HS][e2e] FAILED profile: name never saved")
                return
            }
            NSLog("[HS][e2e] permission prompt left unanswered (no simctl grant for notifications)")
        }
        NSLog("[HS][e2e] step=profile name=\(model.displayName)")

        // 3. Pairing. `invite` mints a code and prints it; the harness signs the second
        //    test number in over REST and calls acceptPair with it.
        let pairMode = defaults.string(forKey: "HSAutoPair") ?? "wait"
        // `stage` is `.loading` until the FIRST pairs snapshot lands. Deciding whether to
        // mint an invite before then reads a state that does not exist yet and silently
        // skips the whole pairing step.
        _ = await waitUntil(timeout: 60, "pairSnapshot", { model.stage != .loading })
        if model.stage == .needsPair, pairMode == "invite" {
            await model.createInvite()
            if let code = model.inviteCode {
                NSLog("[HS][e2e] step=invite code=\(code)")
            } else {
                NSLog("[HS][e2e] FAILED invite: \(model.errorText ?? "no code")")
                return
            }
        }
        guard await waitUntil(timeout: 90, "paired", { model.stage == .main }) else {
            NSLog("[HS][e2e] FAILED pairing: stage=\(model.stage)")
            return
        }
        NSLog("[HS][e2e] step=paired pairId=\(model.pair?.id ?? "-") partner=\(model.partnerName)")

        // 4. The spot. Created through `saveSpot`, so the ADDENDUM §K clamps run.
        if let spec = defaults.string(forKey: "HSAutoSpot"), model.spots.isEmpty {
            let parts = spec.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 2 else {
                NSLog("[HS][e2e] FAILED spot: cannot parse \(spec)")
                return
            }
            let draft = SpotDraft(
                name: defaults.string(forKey: "HSAutoSpotName") ?? "Home",
                lat: parts[0],
                lng: parts[1],
                leadTimeMin: SpotLimits.defaultLeadTimeMin,
                radiusM: SpotLimits.defaultRadiusM
            )
            if let error = await model.saveSpot(existing: nil, draft: draft) {
                NSLog("[HS][e2e] FAILED spot: \(error)")
                return
            }
            _ = await waitUntil(timeout: 30, "spot", { !model.spots.isEmpty })
        }
        NSLog("[HS][e2e] step=spot count=\(model.spots.count) primary=\(model.primarySpot?.name ?? "-")")

        // 5. "I'm coming".
        if defaults.bool(forKey: "HSAutoStartTrip") {
            guard let spot = model.primarySpot else {
                NSLog("[HS][e2e] FAILED startTrip: no spot")
                return
            }
            // The tracker needs a location fix, and the harness only starts feeding the
            // simulated route after it sees `step=ready`. Ask for a fix until one lands.
            guard await waitUntil(timeout: 60, "fix", {
                await model.currentCoordinateForHarness() != nil
            }) else {
                NSLog("[HS][e2e] FAILED startTrip: no location fix")
                return
            }
            if let error = await model.startTrip(to: spot) {
                NSLog("[HS][e2e] FAILED startTrip: \(error)")
                return
            }
            _ = await waitUntil(timeout: 30, "driving", { model.drivingTrip != nil })
            NSLog("[HS][e2e] step=driving tripId=\(model.activeTrip?.id ?? "-")")
        }

        NSLog("[HS][e2e] step=ready")
    }

    // MARK: - Sign-in

    /// `AuthRepository.sendCode` + the emulator's own `verificationCodes` endpoint +
    /// `AuthRepository.verify`. The two repository calls are the real product path; only
    /// the middle step — reading the SMS a human would have received — is synthetic.
    private static func signIn(model: AppViewModel, number: String, host: String) async -> String? {
        if let error = await model.sendCode(to: number) { return error }
        guard let code = await fetchVerificationCode(host: host, number: number) else {
            return "no verification code from the auth emulator"
        }
        NSLog("[HS][e2e] step=otp code=\(code)")
        return await model.verify(code: code)
    }

    private static func fetchVerificationCode(host: String, number: String) async -> String? {
        let project = FirebaseApp.app()?.options.projectID ?? "fin-e8358"
        guard let url = URL(
            string: "http://\(host):\(BackendEnvironment.authPort)/emulator/v1/projects/\(project)/verificationCodes"
        ) else { return nil }
        for _ in 0..<20 {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rows = root["verificationCodes"] as? [[String: Any]] {
                let mine = rows.filter { ($0["phoneNumber"] as? String) == number }
                if let code = mine.last?["code"] as? String { return code }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    // MARK: -

    private static func waitUntil(
        timeout seconds: Int,
        _ label: String,
        _ condition: () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(Double(seconds))
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(400))
        }
        NSLog("[HS][e2e] timeout waiting for \(label)")
        return false
    }
}
#endif
