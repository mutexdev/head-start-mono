package app.headstart.ui.driver

import app.headstart.data.Bands
import app.headstart.data.Eta
import app.headstart.data.Trip
import app.headstart.data.TripAlerts
import com.google.common.truth.Truth.assertThat
import java.time.ZoneId
import org.junit.Test

/** 2023-11-14T22:13:20Z, which is 04:13 am in Asia/Dhaka. */
private const val T0 = 1_700_000_000_000L

private val DHAKA: ZoneId = ZoneId.of("Asia/Dhaka")

private fun trip(
    etaSec: Int = 1080,
    leadTimeMin: Int = 3,
    alerts: TripAlerts = TripAlerts(started = true),
) = Trip(
    id = "trip1",
    pairId = "pair1",
    driverUid = "uidA",
    receiverUid = "uidB",
    spotId = "spot1",
    spotName = "Office",
    spotLat = 0.0,
    spotLng = 0.0,
    spotRadiusM = 100,
    leadTimeMin = leadTimeMin,
    state = "driving",
    startedAtMs = T0,
    eta = Eta(etaSec, T0, false),
    bands = Bands(6600.0, 3850.0, 2750.0),
    phaseHint = "far",
    receiverView = null,
    alerts = alerts,
    routePolyline = null,
)

class LadderTest {

    @Test fun `three rungs, in order, always`() {
        val steps = ladderFor(trip(), nowMs = T0 + 60_000, zone = DHAKA)
        assertThat(steps).hasSize(3)
        assertThat(steps[0].label).isEqualTo("You started driving")
        assertThat(steps[1].label).isEqualTo("10 minutes away")
        assertThat(steps[2].label).isEqualTo("Start walking now")
    }

    @Test fun `a fired rung is done and shows the clock time it fired`() {
        val steps = ladderFor(trip(), nowMs = T0 + 60_000, zone = DHAKA)
        assertThat(steps[0].state).isEqualTo(StepState.DONE)
        assertThat(steps[0].timing).matches("""\d{1,2}:\d{2} (am|pm)""")
    }

    @Test fun `a pending rung counts down from the current eta`() {
        // eta 18 min: tenMin fires in 8 min, leadTime (3 min before arrival) in 15 min
        val steps = ladderFor(trip(etaSec = 1080), nowMs = T0 + 60_000, zone = DHAKA)
        assertThat(steps[1].state).isEqualTo(StepState.PENDING)
        assertThat(steps[1].timing).isEqualTo("in 8 min")
        assertThat(steps[2].state).isEqualTo(StepState.PENDING_LEAD)
        assertThat(steps[2].timing).isEqualTo("in 15 min")
    }

    @Test fun `a rung that is due right now says so instead of showing a negative`() {
        val steps = ladderFor(trip(etaSec = 300), nowMs = T0 + 60_000, zone = DHAKA)
        assertThat(steps[1].timing).isEqualTo("any moment")
    }

    @Test fun `the lead rung carries the receiver's own headstart value`() {
        assertThat(ladderFor(trip(leadTimeMin = 8), nowMs = T0, zone = DHAKA).let { it[2].detail })
            .isEqualTo("8 min")
    }

    @Test fun `fired lead and ten minute rungs both read done`() {
        val steps = ladderFor(
            trip(etaSec = 150, alerts = TripAlerts(started = true, tenMin = true, leadTime = true)),
            nowMs = T0 + 900_000,
            zone = DHAKA,
        )
        assertThat(steps.map { it.state })
            .containsExactly(StepState.DONE, StepState.DONE, StepState.DONE).inOrder()
    }

    @Test fun `a trip with no eta yet leaves the pending rungs blank rather than lying`() {
        val t = trip().copy(eta = null)
        val steps = ladderFor(t, nowMs = T0, zone = DHAKA)
        assertThat(steps[1].timing).isEmpty()
        assertThat(steps[2].timing).isEmpty()
    }
}

class DriverHeadlineTest {

    @Test fun `headline is minutes away and the arrival clock`() {
        val t = trip(etaSec = 1080)
        assertThat(driverEtaMinutes(t)).isEqualTo("18")
        assertThat(driverArrivalLine(t, nowMs = T0, zone = DHAKA))
            .isEqualTo("Arriving at Office around 4:31 am")
    }

    @Test fun `an unknown eta shows a dash rather than zero`() {
        val t = trip().copy(eta = null)
        assertThat(driverEtaMinutes(t)).isEqualTo("—")
        assertThat(driverArrivalLine(t, nowMs = T0, zone = DHAKA))
            .isEqualTo("Working out the route to Office")
    }

    @Test fun `an approximate eta is labelled`() {
        val t = trip().copy(eta = Eta(1080, T0, approximate = true))
        assertThat(driverArrivalLine(t, nowMs = T0, zone = DHAKA))
            .isEqualTo("Arriving at Office around 4:31 am (approx.)")
    }
}
