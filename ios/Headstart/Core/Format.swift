// ios/Headstart/Core/Format.swift
import Foundation

/// Minutes shown on screen. Identical to the server's `min()` in `functions/src/messages.ts`
/// so the number in the push and the number in the app never disagree (decision D5).
public func minutesAway(_ etaSec: Int) -> Int {
    max(1, Int((Double(etaSec) / 60.0).rounded()))
}

/// "7:20" — never negative, always two-digit seconds.
public func formatCountdown(_ totalSec: Int) -> String {
    let s = max(0, totalSec)
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// `DateFormatter` is expensive to build and `clockAt` is called on every tick, so the
/// formatters are cached — but a `DateFormatter` is not `Sendable` and the plan's version
/// (a global `let` whose `timeZone` was reassigned on each call) is a data race that Swift 6
/// rejects outright. Caching behind a lock keeps the performance and the strict-concurrency
/// clean bill of health; the formatter is never handed out, only used under the lock.
private final class HSDateFormatterCache: @unchecked Sendable {
    static let shared = HSDateFormatterCache()

    private let lock = NSLock()
    private var formatters: [String: DateFormatter] = [:]

    func string(from date: Date, format: String, timeZone: TimeZone) -> String {
        let key = "\(format)|\(timeZone.identifier)"
        lock.lock()
        defer { lock.unlock() }
        let formatter: DateFormatter
        if let cached = formatters[key] {
            formatter = cached
        } else {
            let made = DateFormatter()
            // `en_US_POSIX` guarantees "AM"/"PM" regardless of device locale, which we then
            // lowercase to match the artboards ("5:48 pm").
            made.locale = Locale(identifier: "en_US_POSIX")
            made.dateFormat = format
            made.timeZone = timeZone
            formatters[key] = made
            formatter = made
        }
        return formatter.string(from: date)
    }
}

/// "5:48 pm" for a wall-clock instant given in epoch milliseconds.
public func clockAt(_ epochMs: Int64, timeZone: TimeZone = .current) -> String {
    let date = Date(timeIntervalSince1970: Double(epochMs) / 1000)
    return HSDateFormatterCache.shared
        .string(from: date, format: "h:mm a", timeZone: timeZone)
        .lowercased()
}

/// "5:48 pm" for now + eta.
public func arrivalClock(nowMs: Int64, etaSec: Int, timeZone: TimeZone = .current) -> String {
    clockAt(nowMs + Int64(etaSec) * 1_000, timeZone: timeZone)
}

/// "Tuesday evening" — the `DriverHome.dc.html` eyebrow.
public func greetingFor(_ date: Date = Date(), timeZone: TimeZone = .current) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let hour = calendar.component(.hour, from: date)
    let part: String
    switch hour {
    case 5...11: part = "morning"
    case 12...16: part = "afternoon"
    case 17...21: part = "evening"
    default: part = "night"
    }
    let weekday = HSDateFormatterCache.shared.string(from: date, format: "EEEE", timeZone: timeZone)
    return "\(weekday) \(part)"
}

/// "740 m" / "2.9 km" — the `ReceiverTrip` subtitle.
public func formatDistance(_ metres: Double) -> String {
    metres < 1_000
        ? "\(Int(metres.rounded())) m"
        : String(format: "%.1f km", metres / 1_000)
}

/// `receiverView.progressPct` (0…100, but trust nothing) as a 0…1 bar fraction.
public func progressFraction(_ pct: Int) -> Double {
    min(1, max(0, Double(pct) / 100))
}

public func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
