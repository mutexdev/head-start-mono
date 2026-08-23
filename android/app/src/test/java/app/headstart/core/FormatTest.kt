package app.headstart.core

import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

private val DHAKA: ZoneId = ZoneId.of("Asia/Dhaka")

class MinutesAwayTest {
    @Test fun `matches the server rounding rule`() {
        // (seconds, expected minutes) — server: max(1, round(sec/60))
        val table = listOf(
            0 to 1,
            29 to 1,
            30 to 1,
            89 to 1,
            90 to 2,
            170 to 3,
            590 to 10,
            600 to 10,
            1330 to 22,
            3599 to 60,
        )
        for ((sec, expected) in table) {
            assertThat(minutesAway(sec)).isEqualTo(expected)
        }
    }
}

class FormatCountdownTest {
    @Test fun `renders m colon ss and floors at zero`() {
        val table = listOf(
            440 to "7:20",
            0 to "0:00",
            -30 to "0:00",
            9 to "0:09",
            60 to "1:00",
            599 to "9:59",
            3_601 to "60:01",
        )
        for ((sec, expected) in table) {
            assertThat(formatCountdown(sec)).isEqualTo(expected)
        }
    }
}

class ClockTest {
    @Test fun `arrival clock adds the eta and renders lowercase am pm`() {
        // 2026-08-22 17:26 Asia/Dhaka
        val now = LocalDateTime.of(2026, 8, 22, 17, 26).atZone(DHAKA).toInstant().toEpochMilli()
        assertThat(arrivalClock(now, 1_320, DHAKA)).isEqualTo("5:48 pm")
        assertThat(arrivalClock(now, 0, DHAKA)).isEqualTo("5:26 pm")
    }

    @Test fun `clock at renders a stored timestamp`() {
        val at = LocalDateTime.of(2026, 8, 22, 5, 6).atZone(DHAKA).toInstant().toEpochMilli()
        assertThat(clockAt(at, DHAKA)).isEqualTo("5:06 am")
    }

    @Test fun `noon and midnight do not render as 0`() {
        val noon = LocalDateTime.of(2026, 8, 22, 12, 0).atZone(DHAKA).toInstant().toEpochMilli()
        val midnight = LocalDateTime.of(2026, 8, 22, 0, 0).atZone(DHAKA).toInstant().toEpochMilli()
        assertThat(clockAt(noon, DHAKA)).isEqualTo("12:00 pm")
        assertThat(clockAt(midnight, DHAKA)).isEqualTo("12:00 am")
    }
}

class GreetingTest {
    @Test fun `names the day and the part of the day`() {
        val table = listOf(
            LocalDateTime.of(2026, 8, 25, 18, 30) to "Tuesday evening",
            LocalDateTime.of(2026, 8, 25, 8, 0) to "Tuesday morning",
            LocalDateTime.of(2026, 8, 25, 13, 0) to "Tuesday afternoon",
            LocalDateTime.of(2026, 8, 25, 23, 0) to "Tuesday night",
            LocalDateTime.of(2026, 8, 25, 3, 0) to "Tuesday night",
            LocalDateTime.of(2026, 8, 23, 17, 0) to "Sunday evening",
        )
        for ((dt, expected) in table) {
            assertThat(greetingFor(dt)).isEqualTo(expected)
        }
    }
}

class DistanceTest {
    @Test fun `metres under a kilometre, one decimal above`() {
        val table = listOf(
            0.0 to "0 m",
            740.0 to "740 m",
            999.0 to "999 m",
            1_000.0 to "1.0 km",
            2_900.0 to "2.9 km",
            11_049.0 to "11.0 km",
        )
        for ((metres, expected) in table) {
            assertThat(formatDistance(metres)).isEqualTo(expected)
        }
    }
}
