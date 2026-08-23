// ios/Headstart/Tracking/TrackingPhaseController.swift
import Foundation

/// A single OS location fix, stripped of CoreLocation types so this file stays pure
/// Foundation. The Android twin (`TrackingPhaseController.kt`) mirrors it exactly.
public struct LocationFix: Equatable, Sendable {
    public let lat: Double
    public let lng: Double
    public let accuracyM: Double
    public let speedMps: Double
    /// epoch milliseconds
    public let tsMs: Int64

    public init(lat: Double, lng: Double, accuracyM: Double, speedMps: Double, tsMs: Int64) {
        self.lat = lat
        self.lng = lng
        self.accuracyM = accuracyM
        self.speedMps = speedMps
        self.tsMs = tsMs
    }
}

public enum Phase: String, Sendable, Equatable {
    case far
    case near
}

/// Maps to `kCLLocationAccuracyHundredMeters` / `kCLLocationAccuracyBestForNavigation`
/// in `LocationTracker`. Kept abstract so this file never imports CoreLocation.
public enum LocationPriority: Sendable, Equatable {
    case balanced
    case high
}

public struct LocationParams: Equatable, Sendable {
    public let priority: LocationPriority
    public let minIntervalMs: Int64
    public let minDisplacementM: Double

    public init(priority: LocationPriority, minIntervalMs: Int64, minDisplacementM: Double) {
        self.priority = priority
        self.minIntervalMs = minIntervalMs
        self.minDisplacementM = minDisplacementM
    }
}

public enum SkipReason: Sendable, Equatable {
    case lowAccuracy
    case staleTimestamp
    case tooSoon
}

public enum FixDecision: Equatable, Sendable {
    case upload(LocationFix, Phase)
    case skip(SkipReason)
}

/// Upload filter condition 1 from CLIENT_CONTRACT.md.
public let MAX_ACCURACY_M: Double = 100

/// Local safety net: stop tracking after three hours no matter what the server says.
public let TRIP_GUARD_MS: Int64 = 3 * 60 * 60 * 1000

public let LOW_BATTERY_PERCENT = 15

public func haversineMeters(_ aLat: Double, _ aLng: Double, _ bLat: Double, _ bLng: Double) -> Double {
    let r = 6_371_000.0
    let dLat = (bLat - aLat) * .pi / 180
    let dLng = (bLng - aLng) * .pi / 180
    let s = sin(dLat / 2) * sin(dLat / 2)
        + cos(aLat * .pi / 180) * cos(bLat * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
    return 2 * r * asin(min(1.0, sqrt(s)))
}

/// The shared tracking algorithm from CLIENT_CONTRACT.md §"Shared tracking algorithm".
///
/// Not thread-safe by design: `LocationTracker` is `@MainActor` and owns the only
/// instance, so every call is already serialised. Keep this file free of CoreLocation
/// and UIKit imports — it must run in a plain unit test with no simulator services.
public final class TrackingPhaseController {

    private let spotLat: Double
    private let spotLng: Double
    private let nearBandM: Double
    private let startedAtMs: Int64

    public private(set) var phase: Phase = .far
    public private(set) var lowBattery = false

    /// The last fix that was actually written. Skipped fixes never become the baseline.
    public private(set) var lastUploaded: LocationFix?

    /// - Parameters:
    ///   - spotLat: destination latitude, from `trip.spot.lat`
    ///   - spotLng: destination longitude, from `trip.spot.lng`
    ///   - nearBandM: `trip.bands.near`, in metres from the destination
    ///   - startedAtMs: local clock at trip start, for the three-hour guard
    public init(spotLat: Double, spotLng: Double, nearBandM: Double, startedAtMs: Int64) {
        self.spotLat = spotLat
        self.spotLng = spotLng
        self.nearBandM = nearBandM
        self.startedAtMs = startedAtMs
    }

    /// `trip.phaseHint` from the trip document listener. Only "near" does anything.
    public func onServerPhaseHint(_ hint: String?) {
        if hint == "near" { phase = .near }
    }

    /// Feed the OS battery level. Returns true exactly once — on the transition into
    /// low battery — so the caller knows to send `setLowBattery({lowBattery:true})`.
    /// Latches for the rest of the trip (decision D3).
    @discardableResult
    public func onBatteryPercent(_ percent: Int) -> Bool {
        if !lowBattery && percent >= 0 && percent < LOW_BATTERY_PERCENT {
            lowBattery = true
            return true
        }
        return false
    }

    /// Location request parameters for the current phase and battery state.
    /// D2: low battery never downgrades the `near` cadence.
    public func params() -> LocationParams {
        if phase == .near {
            return LocationParams(priority: .high, minIntervalMs: 5_000, minDisplacementM: 10)
        }
        if lowBattery {
            return LocationParams(priority: .balanced, minIntervalMs: 60_000, minDisplacementM: 400)
        }
        return LocationParams(priority: .balanced, minIntervalMs: 30_000, minDisplacementM: 200)
    }

    public func shouldStop(nowMs: Int64) -> Bool {
        nowMs - startedAtMs >= TRIP_GUARD_MS
    }

    /// Runs the accuracy gate, then the phase transition, then the interval/displacement
    /// filter, and reports what the caller should do with this fix.
    public func onFix(_ fix: LocationFix) -> FixDecision {
        // D1: junk fixes are discarded before they can influence anything.
        if fix.accuracyM > MAX_ACCURACY_M { return .skip(.lowAccuracy) }

        // Phase transition — one-way, evaluated against this fix (D4).
        if phase == .far,
           haversineMeters(fix.lat, fix.lng, spotLat, spotLng) <= nearBandM {
            phase = .near
        }

        guard let last = lastUploaded else {
            lastUploaded = fix
            return .upload(fix, phase)
        }
        if fix.tsMs <= last.tsMs { return .skip(.staleTimestamp) }

        let p = params()
        let elapsedMs = fix.tsMs - last.tsMs
        let movedM = haversineMeters(fix.lat, fix.lng, last.lat, last.lng)
        if elapsedMs >= p.minIntervalMs || movedM >= p.minDisplacementM {
            lastUploaded = fix
            return .upload(fix, phase)
        }
        return .skip(.tooSoon)
    }
}
