// ios/HeadstartTests/FormatTests.swift
import XCTest
@testable import Headstart

private let DHAKA = TimeZone(identifier: "Asia/Dhaka")!

private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = DHAKA
    return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

private func ms(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }

final class MinutesAwayTests: XCTestCase {
    func testMatchesTheServerRoundingRule() {
        // server: max(1, round(sec / 60)) — functions/src/messages.ts (decision D5)
        let table: [(Int, Int)] = [
            (0, 1), (29, 1), (30, 1), (89, 1), (90, 2),
            (170, 3), (590, 10), (600, 10), (1330, 22), (3599, 60),
        ]
        for (sec, expected) in table {
            XCTAssertEqual(minutesAway(sec), expected, "\(sec) s")
        }
    }
}

final class FormatCountdownTests: XCTestCase {
    func testRendersMinuteColonSecondsAndFloorsAtZero() {
        let table: [(Int, String)] = [
            (440, "7:20"), (0, "0:00"), (-30, "0:00"),
            (9, "0:09"), (60, "1:00"), (599, "9:59"), (3_601, "60:01"),
        ]
        for (sec, expected) in table {
            XCTAssertEqual(formatCountdown(sec), expected, "\(sec) s")
        }
    }
}

final class ClockTests: XCTestCase {
    func testArrivalClockAddsTheEtaAndRendersLowercaseAmPm() {
        let now = ms(at(2026, 8, 22, 17, 26))
        XCTAssertEqual(arrivalClock(nowMs: now, etaSec: 1_320, timeZone: DHAKA), "5:48 pm")
        XCTAssertEqual(arrivalClock(nowMs: now, etaSec: 0, timeZone: DHAKA), "5:26 pm")
    }

    func testClockAtRendersAStoredTimestamp() {
        XCTAssertEqual(clockAt(ms(at(2026, 8, 22, 5, 6)), timeZone: DHAKA), "5:06 am")
    }

    func testNoonAndMidnightDoNotRenderAsZero() {
        XCTAssertEqual(clockAt(ms(at(2026, 8, 22, 12, 0)), timeZone: DHAKA), "12:00 pm")
        XCTAssertEqual(clockAt(ms(at(2026, 8, 22, 0, 0)), timeZone: DHAKA), "12:00 am")
    }

    func testTheFormatterCacheKeepsTimeZonesApart() {
        // The cache is keyed by format + time zone; a second zone must not inherit the first.
        let utc = TimeZone(identifier: "UTC")!
        let instant = ms(at(2026, 8, 22, 17, 26))       // 17:26 in Dhaka = 11:26 UTC
        XCTAssertEqual(clockAt(instant, timeZone: DHAKA), "5:26 pm")
        XCTAssertEqual(clockAt(instant, timeZone: utc), "11:26 am")
        XCTAssertEqual(clockAt(instant, timeZone: DHAKA), "5:26 pm")
    }
}

final class GreetingTests: XCTestCase {
    func testNamesTheDayAndThePartOfTheDay() {
        let table: [(Date, String)] = [
            (at(2026, 8, 25, 18, 30), "Tuesday evening"),
            (at(2026, 8, 25, 8, 0), "Tuesday morning"),
            (at(2026, 8, 25, 13, 0), "Tuesday afternoon"),
            (at(2026, 8, 25, 23, 0), "Tuesday night"),
            (at(2026, 8, 25, 3, 0), "Tuesday night"),
            (at(2026, 8, 23, 17, 0), "Sunday evening"),
        ]
        for (date, expected) in table {
            XCTAssertEqual(greetingFor(date, timeZone: DHAKA), expected)
        }
    }
}

final class DistanceTests: XCTestCase {
    func testMetresUnderAKilometreOneDecimalAbove() {
        let table: [(Double, String)] = [
            (0, "0 m"), (740, "740 m"), (999, "999 m"),
            (1_000, "1.0 km"), (2_900, "2.9 km"), (11_049, "11.0 km"),
        ]
        for (metres, expected) in table {
            XCTAssertEqual(formatDistance(metres), expected, "\(metres) m")
        }
    }
}

final class ProgressTests: XCTestCase {
    func testProgressFractionIsClampedToZeroOne() {
        XCTAssertEqual(progressFraction(53), 0.53, accuracy: 0.0001)
        XCTAssertEqual(progressFraction(-10), 0, accuracy: 0.0001)
        XCTAssertEqual(progressFraction(140), 1, accuracy: 0.0001)
    }
}
