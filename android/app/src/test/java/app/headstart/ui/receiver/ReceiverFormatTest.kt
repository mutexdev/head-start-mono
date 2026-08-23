package app.headstart.ui.receiver

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class HeadstartCountdownTest {

    @Test fun `counts down from eta minus the receiver's lead time`() {
        // eta 10 min, lead 3 min -> 7 min of sitting still left
        assertThat(headstartSecondsLeft(etaSeconds = 600, leadTimeMin = 3, elapsedSinceUpdateSec = 0))
            .isEqualTo(420)
    }

    @Test fun `ticks locally between server updates`() {
        val table = listOf(
            0 to 440,
            20 to 420,
            120 to 320,
            440 to 0,
        )
        for ((elapsed, expected) in table) {
            assertThat(headstartSecondsLeft(620, 3, elapsed)).isEqualTo(expected)
        }
    }

    @Test fun `never goes negative`() {
        assertThat(headstartSecondsLeft(620, 3, 9_999)).isEqualTo(0)
        assertThat(headstartSecondsLeft(60, 3, 0)).isEqualTo(0)
    }

    @Test fun `a zero lead time counts down to arrival itself`() {
        assertThat(headstartSecondsLeft(600, 0, 0)).isEqualTo(600)
    }
}

class ReceiverStatusTest {

    @Test fun `status line rounds the eta the same way the push does`() {
        assertThat(receiverStatusLine(etaSeconds = 590)).isEqualTo("10 min away")
        assertThat(receiverStatusLine(etaSeconds = 90)).isEqualTo("2 min away")
        assertThat(receiverStatusLine(etaSeconds = 20)).isEqualTo("1 min away")
    }

    @Test fun `walk out state replaces the countdown once the lead time is reached`() {
        assertThat(isWalkOutNow(secondsLeft = 0)).isTrue()
        assertThat(isWalkOutNow(secondsLeft = 1)).isFalse()
    }

    @Test fun `progress is clamped to a percentage`() {
        val table = listOf(-10 to 0, 0 to 0, 53 to 53, 100 to 100, 140 to 100)
        for ((input, expected) in table) {
            assertThat(clampProgressPct(input)).isEqualTo(expected)
        }
    }
}
