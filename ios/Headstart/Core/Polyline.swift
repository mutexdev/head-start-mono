// ios/Headstart/Core/Polyline.swift
import Foundation

// NOTE: the plan doc writes this file against the CoreLocation module and returns
// `[CLLocationCoordinate2D]`. This batch is Foundation-only by rule, so the decoder
// returns `HSCoordinate` — same `latitude`/`longitude` member names, so the map layer
// in a later batch converts with `CLLocationCoordinate2D(latitude:longitude:)` and
// nothing else changes.

/// A plain lat/lng pair. Deliberately not `CLLocationCoordinate2D`: this file must compile
/// and test with no CoreLocation dependency, and `CLLocationCoordinate2D` is not `Equatable`.
public struct HSCoordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Decodes a Google/Google Routes encoded polyline (precision 5) — the format the
/// server stores in `trip.routePolyline`. Mirrors `functions/src/engine/geo.ts`.
/// Never throws: a truncated string returns the points it managed to read, because a
/// half-written document must not take the receiver's trip screen down.
public func decodePolyline(_ encoded: String) -> [HSCoordinate] {
    var points: [HSCoordinate] = []
    let scalars = Array(encoded.unicodeScalars)
    var index = 0
    var lat = 0
    var lng = 0

    func nextDelta() -> Int? {
        var shift = 0
        var result = 0
        while index < scalars.count {
            let byte = Int(scalars[index].value) - 63
            index += 1
            guard byte >= 0 else { return nil }
            result |= (byte & 0x1F) << shift
            shift += 5
            if byte < 0x20 {
                return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            }
            if shift > 30 { return nil }   // malformed run, bail rather than spin
        }
        return nil
    }

    while index < scalars.count {
        guard let dLat = nextDelta(), let dLng = nextDelta() else { break }
        lat += dLat
        lng += dLng
        points.append(HSCoordinate(
            latitude: Double(lat) / 1e5,
            longitude: Double(lng) / 1e5
        ))
    }
    return points
}
