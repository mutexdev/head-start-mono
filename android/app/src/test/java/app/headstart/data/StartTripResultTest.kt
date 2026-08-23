package app.headstart.data

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class StartTripResultTest {

    @Test fun `parses the full startTrip response`() {
        val raw = mapOf<String, Any?>(
            "tripId" to "trip1",
            "bands" to mapOf("far" to 6600.0, "near" to 3850.0, "lead" to 2750.0),
            "etaSeconds" to 1320L,
            "existing" to false,
        )
        val r = startTripResultFrom(raw)!!
        assertThat(r.tripId).isEqualTo("trip1")
        assertThat(r.bands.near).isWithin(1e-9).of(3850.0)
        assertThat(r.etaSeconds).isEqualTo(1320)
        assertThat(r.existing).isFalse()
    }

    @Test fun `tolerates integer bands and a missing existing flag`() {
        val raw = mapOf<String, Any?>(
            "tripId" to "trip1",
            "bands" to mapOf("far" to 6600L, "near" to 3850L, "lead" to 2750L),
            "etaSeconds" to 1320L,
        )
        val r = startTripResultFrom(raw)!!
        assertThat(r.bands.far).isWithin(1e-9).of(6600.0)
        assertThat(r.existing).isFalse()
    }

    @Test fun `reports an existing trip so the UI can jump straight to it`() {
        val raw = mapOf<String, Any?>(
            "tripId" to "trip1",
            "bands" to mapOf("far" to 1.0, "near" to 1.0, "lead" to 1.0),
            "etaSeconds" to 60L,
            "existing" to true,
        )
        assertThat(startTripResultFrom(raw)!!.existing).isTrue()
    }

    @Test fun `a response without a trip id or bands is rejected`() {
        assertThat(startTripResultFrom(mapOf("bands" to mapOf("far" to 1.0)))).isNull()
        assertThat(startTripResultFrom(mapOf("tripId" to "trip1"))).isNull()
        assertThat(startTripResultFrom(emptyMap())).isNull()
    }

    @Test fun `running late minutes are clamped to the contract range`() {
        val table = listOf(0 to 1, 1 to 1, 5 to 5, 60 to 60, 61 to 60, -3 to 1)
        for ((input, expected) in table) {
            assertThat(clampExtraMin(input)).isEqualTo(expected)
        }
    }
}
