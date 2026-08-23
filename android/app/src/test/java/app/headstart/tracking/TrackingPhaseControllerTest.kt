package app.headstart.tracking

import com.google.common.truth.Truth.assertThat
import org.junit.Test

/**
 * The spot sits at (0,0). One degree of latitude is ~111.19 km, so lat 0.001 is ~111 m
 * and lat 0.01 is ~1111 m — handy round numbers for the tables below.
 */
private const val SPOT_LAT = 0.0
private const val SPOT_LNG = 0.0
private const val T0 = 1_700_000_000_000L
private const val NEAR_BAND = 3_850.0

private fun controller(
    nearBandM: Double = NEAR_BAND,
    startedAtMs: Long = T0,
) = TrackingPhaseController(SPOT_LAT, SPOT_LNG, nearBandM, startedAtMs)

private fun fix(
    lat: Double,
    tsMs: Long,
    accuracyM: Double = 10.0,
    speedMps: Double = 12.0,
    lng: Double = 0.0,
) = LocationFix(lat = lat, lng = lng, accuracyM = accuracyM, speedMps = speedMps, tsMs = tsMs)

class HaversineTest {
    @Test fun `identical points are zero metres apart`() {
        assertThat(haversineMeters(1.0, 1.0, 1.0, 1.0)).isWithin(0.001).of(0.0)
    }

    @Test fun `one degree of latitude is about 111 km`() {
        val d = haversineMeters(0.0, 0.0, 1.0, 0.0)
        assertThat(d).isGreaterThan(110_000.0)
        assertThat(d).isLessThan(112_000.0)
    }

    @Test fun `is symmetric`() {
        val a = haversineMeters(23.78, 90.41, 23.75, 90.39)
        val b = haversineMeters(23.75, 90.39, 23.78, 90.41)
        assertThat(a).isWithin(0.0001).of(b)
    }
}

class PhaseTransitionTest {
    @Test fun `starts in far`() {
        assertThat(controller().phase).isEqualTo(Phase.FAR)
    }

    @Test fun `server phase hint near latches the phase`() {
        val c = controller()
        c.onServerPhaseHint("near")
        assertThat(c.phase).isEqualTo(Phase.NEAR)
    }

    @Test fun `server phase hint far does not move the phase back`() {
        val c = controller()
        c.onServerPhaseHint("near")
        c.onServerPhaseHint("far")
        assertThat(c.phase).isEqualTo(Phase.NEAR)
    }

    @Test fun `unknown or null phase hint is ignored`() {
        val c = controller()
        c.onServerPhaseHint(null)
        c.onServerPhaseHint("")
        c.onServerPhaseHint("NEAR")
        assertThat(c.phase).isEqualTo(Phase.FAR)
    }

    @Test fun `distance table drives the phase`() {
        // lat -> expected phase after that single fix, with nearBand = 3850 m
        val table = listOf(
            0.100 to Phase.FAR,   // ~11.1 km out
            0.050 to Phase.FAR,   // ~5.6 km out
            0.0347 to Phase.FAR,  // ~3.86 km out, just outside the band
            0.0346 to Phase.NEAR, // ~3.85 km out, on the band
            0.0100 to Phase.NEAR, // ~1.1 km out
            0.0001 to Phase.NEAR, // ~11 m out
        )
        for ((lat, expected) in table) {
            val c = controller()
            c.onFix(fix(lat, T0))
            assertThat(c.phase).isEqualTo(expected)
        }
    }

    @Test fun `phase never returns to far once near`() {
        val c = controller()
        c.onFix(fix(0.010, T0))                 // inside the band -> NEAR
        assertThat(c.phase).isEqualTo(Phase.NEAR)
        c.onFix(fix(0.100, T0 + 60_000))        // driver overshoots and drives away
        assertThat(c.phase).isEqualTo(Phase.NEAR)
    }

    @Test fun `a low accuracy fix cannot latch the phase (decision D1)`() {
        val c = controller()
        val decision = c.onFix(fix(0.001, T0, accuracyM = 900.0))
        assertThat(decision).isInstanceOf(FixDecision.Skip::class.java)
        assertThat((decision as FixDecision.Skip).reason).isEqualTo(SkipReason.LOW_ACCURACY)
        assertThat(c.phase).isEqualTo(Phase.FAR)
    }
}

class LocationParamsTest {
    @Test fun `parameter table matches the contract`() {
        // (phase, lowBattery) -> expected parameters
        val far = controller()
        assertThat(far.params()).isEqualTo(LocationParams(LocationPriority.BALANCED, 30_000L, 200f))

        val farLow = controller()
        farLow.onBatteryPercent(9)
        assertThat(farLow.params()).isEqualTo(LocationParams(LocationPriority.BALANCED, 60_000L, 400f))

        val near = controller()
        near.onServerPhaseHint("near")
        assertThat(near.params()).isEqualTo(LocationParams(LocationPriority.HIGH, 5_000L, 10f))

        // Decision D2: low battery never downgrades the near phase.
        val nearLow = controller()
        nearLow.onServerPhaseHint("near")
        nearLow.onBatteryPercent(3)
        assertThat(nearLow.params()).isEqualTo(LocationParams(LocationPriority.HIGH, 5_000L, 10f))
    }

    @Test fun `battery reports at or above 15 percent do not trip low battery`() {
        val c = controller()
        assertThat(c.onBatteryPercent(15)).isFalse()
        assertThat(c.onBatteryPercent(100)).isFalse()
        assertThat(c.lowBattery).isFalse()
    }

    @Test fun `low battery is reported exactly once and then latches (decision D3)`() {
        val c = controller()
        assertThat(c.onBatteryPercent(14)).isTrue()
        assertThat(c.onBatteryPercent(9)).isFalse()
        assertThat(c.onBatteryPercent(80)).isFalse()   // charger plugged in mid-trip
        assertThat(c.lowBattery).isTrue()
    }

    @Test fun `a nonsense battery percent is ignored`() {
        val c = controller()
        assertThat(c.onBatteryPercent(-1)).isFalse()
        assertThat(c.lowBattery).isFalse()
    }
}

class UploadFilterTest {
    @Test fun `the first acceptable fix is always uploaded`() {
        val c = controller()
        val d = c.onFix(fix(0.100, T0))
        assertThat(d).isInstanceOf(FixDecision.Upload::class.java)
        assertThat((d as FixDecision.Upload).phase).isEqualTo(Phase.FAR)
    }

    @Test fun `condition 1 - fixes worse than 100 m accuracy are dropped`() {
        val c = controller()
        c.onFix(fix(0.100, T0))
        val table = listOf(
            100.0 to true,    // exactly 100 m is acceptable
            100.1 to false,
            250.0 to false,
        )
        for ((accuracy, acceptable) in table) {
            val d = c.onFix(fix(0.050, T0 + 600_000, accuracyM = accuracy))
            if (acceptable) {
                assertThat(d).isInstanceOf(FixDecision.Upload::class.java)
            } else {
                assertThat((d as FixDecision.Skip).reason).isEqualTo(SkipReason.LOW_ACCURACY)
            }
        }
    }

    @Test fun `condition 2 - a timestamp not strictly greater than the last upload is dropped`() {
        val c = controller()
        c.onFix(fix(0.100, T0 + 60_000))
        val same = c.onFix(fix(0.050, T0 + 60_000))
        assertThat((same as FixDecision.Skip).reason).isEqualTo(SkipReason.STALE_TIMESTAMP)
        val older = c.onFix(fix(0.050, T0 + 30_000))
        assertThat((older as FixDecision.Skip).reason).isEqualTo(SkipReason.STALE_TIMESTAMP)
    }

    @Test fun `condition 3 in far phase - 30 s interval or 200 m displacement`() {
        // Each row: (elapsed ms since last upload, metres moved, expected upload?)
        val table = listOf(
            Triple(1_000L, 10.0, false),
            Triple(1_000L, 199.0, false),
            Triple(1_000L, 201.0, true),   // displacement wins
            Triple(29_999L, 5.0, false),
            Triple(30_000L, 5.0, true),    // interval wins
            Triple(120_000L, 0.0, true),
        )
        for ((elapsed, metres, expected) in table) {
            val c = controller()
            c.onFix(fix(0.100, T0))
            // 0.100 lat is the anchor; move north by `metres` (1 deg lat ~ 111_190 m).
            val lat = 0.100 + metres / 111_190.0
            val d = c.onFix(fix(lat, T0 + elapsed))
            val uploaded = d is FixDecision.Upload
            assertThat(uploaded).isEqualTo(expected)
        }
    }

    @Test fun `condition 3 in near phase - 5 s interval or 10 m displacement`() {
        val table = listOf(
            Triple(1_000L, 2.0, false),
            Triple(1_000L, 11.0, true),
            Triple(4_999L, 1.0, false),
            Triple(5_000L, 1.0, true),
        )
        for ((elapsed, metres, expected) in table) {
            val c = controller()
            c.onServerPhaseHint("near")
            c.onFix(fix(0.0100, T0))
            val lat = 0.0100 + metres / 111_190.0
            val d = c.onFix(fix(lat, T0 + elapsed))
            assertThat(d is FixDecision.Upload).isEqualTo(expected)
        }
    }

    @Test fun `condition 3 in far phase on low battery - 60 s interval or 400 m displacement`() {
        val table = listOf(
            Triple(30_000L, 5.0, false),
            Triple(59_999L, 5.0, false),
            Triple(60_000L, 5.0, true),
            Triple(1_000L, 399.0, false),
            Triple(1_000L, 401.0, true),
        )
        for ((elapsed, metres, expected) in table) {
            val c = controller()
            c.onBatteryPercent(11)
            c.onFix(fix(0.100, T0))
            val lat = 0.100 + metres / 111_190.0
            val d = c.onFix(fix(lat, T0 + elapsed))
            assertThat(d is FixDecision.Upload).isEqualTo(expected)
        }
    }

    @Test fun `a skipped fix does not become the new baseline`() {
        val c = controller()
        c.onFix(fix(0.100, T0))
        c.onFix(fix(0.1001, T0 + 1_000))  // ~11 m, skipped in far phase
        assertThat(c.lastUploaded?.tsMs).isEqualTo(T0)
        // 30 s after the *uploaded* fix, not after the skipped one:
        val d = c.onFix(fix(0.1001, T0 + 30_000))
        assertThat(d).isInstanceOf(FixDecision.Upload::class.java)
        assertThat(c.lastUploaded?.tsMs).isEqualTo(T0 + 30_000)
    }

    @Test fun `crossing into the near band applies near rules to that same fix (decision D4)`() {
        val c = controller()
        c.onFix(fix(0.100, T0))                       // far baseline
        val d = c.onFix(fix(0.0100, T0 + 6_000))      // enters the band, 6 s later
        assertThat(c.phase).isEqualTo(Phase.NEAR)
        assertThat(d).isInstanceOf(FixDecision.Upload::class.java)
        assertThat((d as FixDecision.Upload).phase).isEqualTo(Phase.NEAR)
    }
}

class TripGuardTest {
    @Test fun `three hour local guard`() {
        val c = controller(startedAtMs = T0)
        assertThat(c.shouldStop(T0)).isFalse()
        assertThat(c.shouldStop(T0 + 3 * 60 * 60 * 1000 - 1)).isFalse()
        assertThat(c.shouldStop(T0 + 3 * 60 * 60 * 1000)).isTrue()
        assertThat(c.shouldStop(T0 + 5 * 60 * 60 * 1000)).isTrue()
    }
}

class RealisticDriveTest {
    /**
     * 11 km straight-line approach at ~12 m/s with a 1 Hz location stream, low accuracy
     * noise every 20th fix. Asserts the shape of the whole trip rather than one branch.
     *
     * NOTE (deviation from the plan doc): the plan asserted `uploads < 160`, reasoning that
     * the near phase would be governed by its 5 s interval. That is wrong. Condition 3 of the
     * contract's upload filter is an OR, and at ~12.2 m/s the near phase's 10 m displacement
     * clause fires on *every* 1 Hz fix — so the near phase deliberately uploads at ~1 Hz.
     * Measured total is 334. The assertions below are split per phase so they still fail loudly
     * if the far-phase throttle regresses, instead of just being widened to hide the miss.
     */
    @Test fun `a simulated drive uploads a sane number of fixes and ends in near`() {
        val c = controller()
        var uploads = 0
        var farUploads = 0
        var nearUploads = 0
        var lowAccuracySkips = 0
        val totalMetres = 11_000.0
        val steps = 900                                  // 900 s of driving
        for (i in 0 until steps) {
            val remaining = totalMetres * (1.0 - i / steps.toDouble())
            val lat = remaining / 111_190.0
            val accuracy = if (i % 20 == 0) 400.0 else 12.0
            when (val d = c.onFix(fix(lat, T0 + i * 1_000L, accuracyM = accuracy))) {
                is FixDecision.Upload -> {
                    uploads++
                    if (d.phase == Phase.NEAR) nearUploads++ else farUploads++
                }
                is FixDecision.Skip ->
                    if (d.reason == SkipReason.LOW_ACCURACY) lowAccuracySkips++
            }
        }
        assertThat(c.phase).isEqualTo(Phase.NEAR)
        assertThat(uploads).isEqualTo(farUploads + nearUploads)

        // Every 20th fix is junk and can never be uploaded (condition 1, decision D1).
        assertThat(lowAccuracySkips).isEqualTo(steps / 20)
        assertThat(uploads).isAtMost(steps - lowAccuracySkips)

        // Far phase (~585 s): displacement-throttled to roughly one upload per 200 m (~16 s),
        // i.e. far fewer than one per fix. This is the battery-saving half of the contract.
        assertThat(farUploads).isGreaterThan(20)
        assertThat(farUploads).isLessThan(60)

        // Near phase (~314 s): ~1 Hz, because 12.2 m per second clears the 10 m displacement.
        assertThat(nearUploads).isGreaterThan(250)
        assertThat(nearUploads).isLessThan(315)
    }
}
