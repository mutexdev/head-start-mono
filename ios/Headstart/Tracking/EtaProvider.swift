// ios/Headstart/Tracking/EtaProvider.swift
//
// Decision D7: the DRIVER'S PHONE computes the ETA, so the server can skip its Google Routes
// call entirely. CLIENT_CONTRACT_ADDENDUM.md §F makes that a hard guarantee — a valid client
// `etaSec` means the server performs zero routing calls for that position — so this file is
// the reason iOS trips cost the backend nothing to route.
//
// `MKDirections.calculateETA` is free, traffic-aware and needs no Maps API key. It is called
// at most once per ACCEPTED position (≥ 5 s apart in `near`, ≥ 30 s in `far`), never per raw
// fix, which keeps us well inside MapKit's undocumented throttle.
//
// It still needs live network and it still throttles, so an automated drive that depended on
// it would be flaky. Hence `EtaProviding`: the headless validation in a later batch launches
// with `-HSFakeEta 900` and every uploaded position deterministically carries `etaSec: 900`.
// A run WITHOUT the flag exercises the real MapKit path.
//
// On any failure — no route, throttled, offline — the answer is nil, the position document
// simply omits `etaSec`, and the server falls back to its own routing. That is the documented
// fallback, not an error worth surfacing to a person, so it is logged `[ETA]` and nowhere else
// (Task 20 Step 2: log on FAILURE only, never on success — a success log would fire on every
// upload for the length of the drive).

import Foundation
import MapKit

/// Coordinates in, seconds out. Deliberately plain `Double`s rather than
/// `CLLocationCoordinate2D`: `LocationTracker` already speaks in `LocationFix` and `TripSpot`,
/// and a non-`Sendable` CoreLocation struct in a `Sendable` protocol is a fight for nothing.
public protocol EtaProviding: Sendable {
    /// Seconds of driving time, or nil when no ETA could be produced.
    func etaSeconds(fromLat: Double, fromLng: Double, toLat: Double, toLng: Double) async -> Int?
}

// MARK: - MapKit

public struct MapKitEtaProvider: EtaProviding {

    public init() {}

    public func etaSeconds(fromLat: Double, fromLng: Double, toLat: Double, toLng: Double) async -> Int? {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: fromLat, longitude: fromLng))
        )
        request.destination = MKMapItem(
            placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: toLat, longitude: toLng))
        )
        request.transportType = .automobile
        request.departureDate = Date()

        do {
            let response = try await MKDirections(request: request).calculateETA()
            let seconds = Int(response.expectedTravelTime.rounded())
            return seconds > 0 ? seconds : nil
        } catch {
            NSLog("[HS][ETA] calculateETA failed: %@", error.localizedDescription)
            return nil
        }
    }
}

// MARK: - Fake

/// Answers the same number every time, or nil to simulate a permanent MapKit failure.
/// Used by previews, by the unit tests, and by the headless drive via `-HSFakeEta`.
public struct FakeEtaProvider: EtaProviding {
    private let seconds: Int?

    public init(seconds: Int?) { self.seconds = seconds }

    public func etaSeconds(fromLat: Double, fromLng: Double, toLat: Double, toLng: Double) async -> Int? {
        seconds
    }
}

// MARK: - Launch-argument selection

/// `ServiceLocator` asks this which provider to build. Pure and injectable so the launch-arg
/// contract is unit-tested rather than discovered during a drive.
///
/// `xcrun simctl launch <udid> com.mutexdev.headstart -HSFakeEta 900` — `UserDefaults` parses
/// `-key value` launch arguments itself, so there is nothing to scrape out of
/// `ProcessInfo.arguments`.
///
///   * argument absent        → real MapKit
///   * `-HSFakeEta 900`       → always 900 s
///   * `-HSFakeEta 0`         → always nil, i.e. "MapKit is permanently down", which is how
///                              the `etaSec`-omitted branch of the position document is driven
public enum EtaProviderFactory {

    public static let launchArgumentKey = "HSFakeEta"

    /// nil when the launch argument is absent — the caller then builds `MapKitEtaProvider`.
    public static func fakeSeconds(defaults: UserDefaults = .standard) -> Int?? {
        guard defaults.object(forKey: launchArgumentKey) != nil else { return nil }
        let value = defaults.integer(forKey: launchArgumentKey)
        return .some(value > 0 ? value : nil)
    }

    public static func resolve(defaults: UserDefaults = .standard) -> EtaProviding {
        guard let fake = fakeSeconds(defaults: defaults) else { return MapKitEtaProvider() }
        return FakeEtaProvider(seconds: fake)
    }

    /// True when the fake is in play — printed once at launch so a drive log says which
    /// provider produced its numbers.
    public static func isFaked(defaults: UserDefaults = .standard) -> Bool {
        fakeSeconds(defaults: defaults) != nil
    }
}
