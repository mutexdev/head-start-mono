// ios/Headstart/Tracking/BatteryProvider.swift
//
// NOT IN THE PLAN DOC, AND REQUIRED.
//
// `UIDevice.current.batteryLevel` returns -1 on the Simulator — always, with monitoring
// enabled or not. The Simulator has no battery to report. That single fact makes three
// contract rules untestable anywhere in the M1 verification path:
//
//   * CLIENT_CONTRACT.md §Shared tracking algorithm, row 3 of the parameters table:
//     "far + battery < 15 % → balanced / 60 s / 400 m"
//   * CLIENT_CONTRACT.md §Battery: "call setLowBattery({lowBattery:true}) ONCE per trip"
//     (CLIENT_CONTRACT_ADDENDUM.md §L pins the latch to the trip repository, keyed by tripId)
//   * decision D2: low battery must NEVER downgrade the `near` cadence
//
// Behind this protocol they become first-class asserted behaviour instead of dead code:
// `xcrun simctl launch <udid> com.mutexdev.headstart -HSFakeBatteryPct 9` makes the whole
// app behave as if the phone were at 9 %, and `BatteryProviderTests` drives the latch and the
// D2 rule through the same seam.
//
// Isolation: the getter is `@MainActor`. `UIDevice` is main-actor-isolated, `LocationTracker`
// is `@MainActor`, and the alternative — a nonisolated getter wrapping `assumeIsolated` —
// would be a runtime trap waiting for the first caller that is not on the main actor. The
// protocol itself stays `Sendable` so a provider can be stored anywhere.

import Foundation
import UIKit

public protocol BatteryProviding: Sendable {
    /// 0…100, or nil when the OS has no answer (the Simulator, or monitoring not yet settled).
    @MainActor var percent: Int? { get }

    /// Called when a trip starts / ends. The device implementation toggles
    /// `isBatteryMonitoringEnabled`; the fake does nothing.
    @MainActor func startMonitoring()
    @MainActor func stopMonitoring()
}

public extension BatteryProviding {
    @MainActor func startMonitoring() {}
    @MainActor func stopMonitoring() {}
}

/// The real thing. Correct on a device, permanently nil on the Simulator — which is exactly
/// why `FakeBatteryProvider` exists rather than this being the only implementation.
public struct DeviceBatteryProvider: BatteryProviding {

    public init() {}

    @MainActor public var percent: Int? {
        let level = UIDevice.current.batteryLevel
        // -1 means "unknown": monitoring off, or a Simulator. Never report it as 0 %, or a
        // simulator run would latch low battery on the very first fix.
        guard level >= 0 else { return nil }
        return Int((level * 100).rounded())
    }

    @MainActor public func startMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    @MainActor public func stopMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = false
    }
}

/// Reports whatever it was built with. `percent: nil` reproduces the Simulator.
public struct FakeBatteryProvider: BatteryProviding {
    private let value: Int?

    public init(percent: Int?) { self.value = percent }

    @MainActor public var percent: Int? { value }
}

/// `ServiceLocator` asks this which provider to build. Pure and injectable, so the launch-arg
/// contract is unit-tested rather than discovered during a drive.
///
///   * argument absent            → `DeviceBatteryProvider`
///   * `-HSFakeBatteryPct 9`      → a phone permanently at 9 %
///   * `-HSFakeBatteryPct 80`     → a healthy phone, i.e. the low-battery row never fires
///   * `-HSFakeBatteryPct -1`     → reproduces the Simulator's "no answer" on a device build
public enum BatteryProviderFactory {

    public static let launchArgumentKey = "HSFakeBatteryPct"

    /// Outer nil: no launch argument. Inner nil: the argument asked for "unknown".
    public static func fakePercent(defaults: UserDefaults = .standard) -> Int?? {
        guard defaults.object(forKey: launchArgumentKey) != nil else { return nil }
        let value = defaults.integer(forKey: launchArgumentKey)
        return .some(value >= 0 ? min(100, value) : nil)
    }

    public static func resolve(defaults: UserDefaults = .standard) -> BatteryProviding {
        guard let fake = fakePercent(defaults: defaults) else { return DeviceBatteryProvider() }
        return FakeBatteryProvider(percent: fake)
    }

    public static func isFaked(defaults: UserDefaults = .standard) -> Bool {
        fakePercent(defaults: defaults) != nil
    }
}
