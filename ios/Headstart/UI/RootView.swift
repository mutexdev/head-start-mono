// ios/Headstart/UI/RootView.swift
//
// The route state machine, and the only place in the app that navigates.
//
//   signed out            -> onboarding  (Welcome -> Phone -> Verify)
//   signed in, no name    -> ProfileView (the two permission primers live here)
//   signed in, no pair    -> pairing     (PairEmpty -> PairInvite | PairEnter)
//   paired, no live trip  -> HomeView
//   paired, driving trip  -> DriverTripView | ReceiverTripView, by role
//
// PUSH NAVIGATION. `PushRouter` has already decided where an arriving alert wants the app
// to be (`destination`), and nothing here parses a userInfo dictionary — that funnel is
// `PushRouter.handle(userInfo:)` and there is no other. This view reacts to the decision
// and then calls `clearDestination()`; without that clear, a relaunch replays the last
// alert's navigation. `showDriverNudge` is the separate `didYouLeave` sheet flag and is
// cleared with `dismissDriverNudge()`.

import SwiftUI
import CoreLocation

public struct RootView: View {

    @StateObject private var model = AppViewModel()
    @StateObject private var router = PushRouter.shared

    // Onboarding
    @State private var onboardingPath: [OnboardingRoute] = []
    @State private var wantsToJoin = false
    // Pairing
    @State private var pairingPath: [PairingRoute] = []
    // Main
    @State private var mainPath: [MainRoute] = []
    @State private var nudgeVisible = false

    enum OnboardingRoute: Hashable { case phone, verify }
    enum PairingRoute: Hashable { case invite, enter }
    enum MainRoute: Hashable {
        case settings
        case spots
        case addSpot
        case editSpot(String)
    }

    public init() {}

    public var body: some View {
        Group {
            switch model.stage {
            case .loading:
                loading
            case .signedOut:
                onboarding
            case .needsProfile:
                ProfileView(
                    onBack: { model.signOut() },
                    onContinue: { name in await model.completeProfile(name: name) }
                )
            case .needsPair:
                pairing
            case .main:
                main
            }
        }
        .environmentObject(model)
        .preferredColorScheme(.dark)
        .onChange(of: router.destination) { _, destination in
            navigate(to: destination)
        }
        .onChange(of: router.showDriverNudge) { _, showing in
            // Only the driver of the live trip ever sees the sheet.
            nudgeVisible = showing && model.myRoleInTrip == .driver
            if showing && !nudgeVisible { router.dismissDriverNudge() }
        }
        .task {
            // A push can land before this view exists; consume whatever is already there.
            navigate(to: router.destination)
            #if DEBUG
            await E2EAutopilot.runIfRequested(model: model)
            #endif
        }
    }

    /// `PushRouter` decided; this applies it and consumes it.
    private func navigate(to destination: PushDestination) {
        switch destination {
        case .ignore:
            return
        case .home:
            mainPath.removeAll()
        case .trip:
            // The trip screen IS the root of the main stack when a trip is driving, so
            // "go to the trip" means "pop everything above the root".
            mainPath.removeAll()
        case .driverNudge:
            mainPath.removeAll()
            nudgeVisible = model.myRoleInTrip == .driver
        }
        router.clearDestination()
    }

    private var loading: some View {
        ZStack {
            HS.base.ignoresSafeArea()
            ProgressView().tint(HS.text2)
        }
    }

    // MARK: - Onboarding

    private var onboarding: some View {
        NavigationStack(path: $onboardingPath) {
            WelcomeView(
                onGetStarted: {
                    wantsToJoin = false
                    onboardingPath = [.phone]
                },
                onHaveCode: {
                    wantsToJoin = true
                    onboardingPath = [.phone]
                }
            )
            .navigationDestination(for: OnboardingRoute.self) { route in
                switch route {
                case .phone:
                    PhoneView(
                        onBack: { if !onboardingPath.isEmpty { onboardingPath.removeLast() } },
                        onSend: { e164 in
                            let error = await model.sendCode(to: e164)
                            if error == nil { onboardingPath.append(.verify) }
                            return error
                        }
                    )
                case .verify:
                    VerifyView(
                        displayNumber: model.pendingNumber ?? "your number",
                        onBack: { if !onboardingPath.isEmpty { onboardingPath.removeLast() } },
                        onVerify: { code in await model.verify(code: code) },
                        onResend: { await model.resendCode() }
                    )
                }
            }
        }
    }

    // MARK: - Pairing

    private var pairing: some View {
        NavigationStack(path: $pairingPath) {
            PairEmptyView(
                onInvite: {
                    pairingPath = [.invite]
                    Task { await model.createInvite() }
                },
                onEnterCode: { pairingPath = [.enter] }
            )
            .navigationDestination(for: PairingRoute.self) { route in
                switch route {
                case .invite:
                    PairInviteView(
                        code: model.inviteCode,
                        errorText: model.errorText,
                        onBack: { if !pairingPath.isEmpty { pairingPath.removeLast() } },
                        onRetry: { Task { await model.createInvite() } }
                    )
                case .enter:
                    PairEnterView(
                        onBack: { if !pairingPath.isEmpty { pairingPath.removeLast() } },
                        onPair: { code in await model.acceptInvite(code: code) }
                    )
                }
            }
        }
        .onAppear {
            // "I have an invite code" on Welcome remembers where the user was going.
            if wantsToJoin, pairingPath.isEmpty {
                wantsToJoin = false
                pairingPath = [.enter]
            }
        }
    }

    // MARK: - Main

    private var main: some View {
        NavigationStack(path: $mainPath) {
            tripOrHome
                .navigationDestination(for: MainRoute.self) { route in
                    switch route {
                    case .settings:
                        SettingsView(
                            partnerName: model.partnerName,
                            pairedSince: model.pair?.createdAt,
                            onBack: { if !mainPath.isEmpty { mainPath.removeLast() } },
                            onUnpair: { await model.unpair() },
                            onTestAlert: { await model.sendTestAlert() },
                            onSignOut: { model.signOut() }
                        )
                    case .spots:
                        SpotsView(
                            spots: model.spots,
                            partnerName: model.partnerName,
                            onBack: { if !mainPath.isEmpty { mainPath.removeLast() } },
                            onAdd: { mainPath.append(.addSpot) },
                            onEdit: { spot in mainPath.append(.editSpot(spot.id)) }
                        )
                    case .addSpot:
                        AsyncSpotEditor(existing: nil) {
                            if !mainPath.isEmpty { mainPath.removeLast() }
                        }
                    case .editSpot(let spotId):
                        AsyncSpotEditor(existing: model.spots.first { $0.id == spotId }) {
                            if !mainPath.isEmpty { mainPath.removeLast() }
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var tripOrHome: some View {
        if let trip = model.drivingTrip, let role = model.myRoleInTrip {
            switch role {
            case .driver:
                DriverTripView(
                    trip: trip,
                    partnerName: model.partnerName,
                    latestReply: model.latestReplyFromPartner,
                    onRunningLate: { minutes in await model.runningLate(extraMin: minutes) },
                    onCancel: { await model.endTrip(reason: .cancelled) },
                    onArrived: { await model.endTrip(reason: .arrived) }
                )
                .sheet(isPresented: $nudgeVisible, onDismiss: { router.dismissDriverNudge() }) {
                    DriverNudgeSheet(
                        partnerName: model.partnerName,
                        onOnMyWay: {
                            nudgeVisible = false
                            router.dismissDriverNudge()
                        },
                        onCancelTrip: {
                            let error = await model.endTrip(reason: .cancelled)
                            if error == nil {
                                nudgeVisible = false
                                router.dismissDriverNudge()
                            }
                            return error
                        }
                    )
                }
            case .receiver:
                ReceiverTripView(
                    trip: trip,
                    partnerName: model.partnerName,
                    onReply: { kind, text in await model.sendReply(kind: kind, text: text) }
                )
            }
        } else {
            HomeView(
                onSettings: { mainPath.append(.settings) },
                onSpots: { mainPath.append(.spots) }
            )
        }
    }
}

/// `SpotEditView` needs a starting coordinate for its map, and getting one is asynchronous.
private struct AsyncSpotEditor: View {
    @EnvironmentObject private var model: AppViewModel
    let existing: Spot?
    let onDone: () -> Void

    @State private var startCoordinate: CLLocationCoordinate2D?

    var body: some View {
        Group {
            if let startCoordinate {
                SpotEditView(
                    existing: existing,
                    startCoordinate: startCoordinate,
                    onBack: onDone,
                    onSave: { draft in
                        let error = await model.saveSpot(existing: existing, draft: draft)
                        if error == nil { onDone() }
                        return error
                    },
                    onDelete: existing.map { spot in
                        {
                            let error = await model.deleteSpot(spot)
                            if error == nil { onDone() }
                            return error
                        }
                    }
                )
            } else {
                ZStack {
                    HS.base.ignoresSafeArea()
                    ProgressView().tint(HS.text2)
                }
            }
        }
        .task { startCoordinate = await model.startCoordinate() }
    }
}
