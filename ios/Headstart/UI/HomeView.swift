// ios/Headstart/UI/HomeView.swift
//
// Home when no trip is running.
//
// DELIBERATE DEVIATION FROM THE ARTBOARDS, agreed platform-wide (iOS plan doc line 81;
// Android does the same): `DriverHome.dc.html` and `ReceiverHome.dc.html` are drawn as two
// unconnected screens with no way to move between them. Either paired person can drive —
// that is the entire premise — so Home carries a 44 pt segmented control and remembers the
// choice.
//
// The persistence lives in `HomeRoleSwitch` (`@AppStorage(HomeRole.storageKey)`), written
// in the batch that built the two home screens. This view reads the SAME key so its own
// body re-renders when the switch writes it — one truth, no duplicate state in
// `AppViewModel`, and an active trip forces the matching role so a driver cannot flip to
// "I'm waiting" while their own position is uploading.

import SwiftUI

public struct HomeView: View {

    @EnvironmentObject private var model: AppViewModel
    @AppStorage(HomeRole.storageKey) private var storedRole = HomeRole.driving.rawValue

    private let onSettings: () -> Void
    private let onSpots: () -> Void

    public init(onSettings: @escaping () -> Void, onSpots: @escaping () -> Void) {
        self.onSettings = onSettings
        self.onSpots = onSpots
    }

    /// nil when no trip is running; otherwise the role the live trip gives this user.
    private var forced: HomeRole? {
        guard model.activeTrip != nil, let role = model.myRoleInTrip else { return nil }
        return role == .driver ? .driving : .waiting
    }

    private var role: HomeRole { forced ?? HomeRole(rawValue: storedRole) ?? .driving }

    public var body: some View {
        ZStack {
            HS.base.ignoresSafeArea()
            VStack(spacing: 0) {
                HomeRoleSwitch(forced: forced)
                    .padding(.horizontal, HS.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                if role == .driving {
                    DriverHomeView(
                        myName: model.displayName,
                        partnerName: model.partnerName,
                        spots: model.spots,
                        armedSpotName: model.armedTrip?.spot.name,
                        onSettings: onSettings,
                        onStart: { spot in await model.startTrip(to: spot) },
                        onManageSpots: onSpots
                    )
                } else {
                    ReceiverHomeView(
                        partnerName: model.partnerName,
                        spot: model.primarySpot,
                        armed: model.armedTrip != nil,
                        onSettings: onSettings,
                        onChangeLeadTime: { minutes in
                            guard let spot = model.primarySpot else { return nil }
                            return await model.setLeadTime(minutes, on: spot)
                        },
                        onPingMe: {
                            guard let spot = model.primarySpot else {
                                return "Add a pickup spot first."
                            }
                            return await model.armTrip(to: spot)
                        },
                        onOpenSpots: onSpots
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
    }
}
