package app.headstart.core

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class HeadstartErrorTest {

    @Test fun `every contract error code maps to its own case`() {
        // CLIENT_CONTRACT.md: "Error codes returned as the callable's message"
        // plus `bad-reply` from the M1 addendum §O.
        val table = listOf(
            "not-paired" to HeadstartError.NotPaired,
            "trip-active" to HeadstartError.TripActive,
            "spot-not-found" to HeadstartError.SpotNotFound,
            "bad-code" to HeadstartError.BadCode,
            "own-code" to HeadstartError.OwnCode,
            "driver-only" to HeadstartError.DriverOnly,
            "trip-not-found" to HeadstartError.TripNotFound,
            "bad-coords" to HeadstartError.BadCoords,
            "bad-name" to HeadstartError.BadName,
            "bad-token" to HeadstartError.BadToken,
            "bad-reply" to HeadstartError.BadReply,
        )
        for ((message, expected) in table) {
            assertThat(headstartErrorFor(message)).isSameInstanceAs(expected)
        }
    }

    @Test fun `surrounding whitespace and wrapper text still resolve`() {
        assertThat(headstartErrorFor("  bad-code  ")).isSameInstanceAs(HeadstartError.BadCode)
        assertThat(headstartErrorFor("INVALID_ARGUMENT: bad-code")).isSameInstanceAs(HeadstartError.BadCode)
    }

    @Test fun `unauthenticated and network beat any message`() {
        assertThat(headstartErrorFor("bad-code", isUnauthenticated = true))
            .isSameInstanceAs(HeadstartError.Unauthenticated)
        assertThat(headstartErrorFor("bad-code", isNetwork = true))
            .isSameInstanceAs(HeadstartError.Offline)
    }

    @Test fun `an unrecognised message becomes Unknown and keeps the raw code`() {
        val e = headstartErrorFor("kaboom")
        assertThat(e).isInstanceOf(HeadstartError.Unknown::class.java)
        assertThat(e.code).isEqualTo("kaboom")
        assertThat(e.userMessage).isEqualTo("Something went wrong. Try again.")
    }

    @Test fun `a null message becomes Unknown`() {
        assertThat(headstartErrorFor(null)).isInstanceOf(HeadstartError.Unknown::class.java)
    }

    @Test fun `every case has a sentence a user can read`() {
        val all = listOf(
            HeadstartError.NotPaired, HeadstartError.TripActive, HeadstartError.SpotNotFound,
            HeadstartError.BadCode, HeadstartError.OwnCode, HeadstartError.DriverOnly,
            HeadstartError.TripNotFound, HeadstartError.BadCoords, HeadstartError.BadName,
            HeadstartError.BadToken, HeadstartError.BadReply,
            HeadstartError.Unauthenticated, HeadstartError.Offline,
            HeadstartError.InvalidPhone, HeadstartError.InvalidSmsCode,
            HeadstartError.SmsQuotaExceeded, HeadstartError.SessionExpired,
        )
        for (e in all) {
            assertThat(e.userMessage).isNotEmpty()
            assertThat(e.userMessage.first().isUpperCase()).isTrue()
            assertThat(e.userMessage).doesNotContain("-")
        }
    }
}
