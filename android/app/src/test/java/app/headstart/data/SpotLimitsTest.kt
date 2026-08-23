package app.headstart.data

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class SpotLimitsTest {

    @Test fun `lead time is clamped to the contract range`() {
        val table = listOf(
            -5 to 1,
            0 to 1,
            1 to 1,
            3 to 3,
            30 to 30,
            31 to 30,
            999 to 30,
        )
        for ((input, expected) in table) {
            assertThat(SpotLimits.clampLeadTimeMin(input)).isEqualTo(expected)
        }
    }

    @Test fun `radius is clamped to the contract range`() {
        val table = listOf(
            0 to 50,
            49 to 50,
            50 to 50,
            100 to 100,
            500 to 500,
            501 to 500,
        )
        for ((input, expected) in table) {
            assertThat(SpotLimits.clampRadiusM(input)).isEqualTo(expected)
        }
    }

    @Test fun `the radius stepper cycles through its presets and wraps`() {
        assertThat(SpotLimits.nextRadius(50)).isEqualTo(100)
        assertThat(SpotLimits.nextRadius(100)).isEqualTo(200)
        assertThat(SpotLimits.nextRadius(200)).isEqualTo(300)
        assertThat(SpotLimits.nextRadius(300)).isEqualTo(500)
        assertThat(SpotLimits.nextRadius(500)).isEqualTo(50)
        assertThat(SpotLimits.nextRadius(137)).isEqualTo(50)  // anything unexpected restarts
    }

    @Test fun `spot names are trimmed and length-checked`() {
        assertThat(SpotLimits.validName("  Office  ")).isEqualTo("Office")
        assertThat(SpotLimits.validName("")).isNull()
        assertThat(SpotLimits.validName("   ")).isNull()
        assertThat(SpotLimits.validName("x".repeat(40))).isEqualTo("x".repeat(40))
        assertThat(SpotLimits.validName("x".repeat(41))).isNull()
    }

    @Test fun `coordinates must be on the planet`() {
        assertThat(SpotLimits.validCoords(23.78, 90.41)).isTrue()
        assertThat(SpotLimits.validCoords(0.0, 0.0)).isTrue()
        assertThat(SpotLimits.validCoords(90.1, 0.0)).isFalse()
        assertThat(SpotLimits.validCoords(0.0, 180.1)).isFalse()
        assertThat(SpotLimits.validCoords(Double.NaN, 0.0)).isFalse()
    }
}
