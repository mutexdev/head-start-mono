// ios/Headstart/HeadstartApp.swift
//
// `AppDelegate` has already run `FirebaseApp.configure()`, pointed Auth/Firestore/Functions
// at whichever backend `BackendEnvironment` selected, and forced `ServiceLocator.shared`
// into existence, by the time this scene body is first evaluated. Nothing here may touch
// Firebase before that.
//
// `ServiceLocator` is published as an `EnvironmentObject` once, here. `AppViewModel` takes
// it through its default argument rather than the environment, because it is created as a
// `@StateObject` inside `RootView` and a `@StateObject`'s initial value cannot read the
// environment.

import SwiftUI

@main
struct HeadstartApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ServiceLocator.shared)
        }
    }
}
