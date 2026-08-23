package app.headstart.data

import com.google.common.truth.Truth.assertThat
import org.junit.Test

private const val T0 = 1_700_000_000_000L

class PairMapperTest {
    private val raw = mapOf<String, Any?>(
        "members" to listOf("uidA", "uidB"),
        "status" to "active",
        "inviteCode" to "K7M2QP",
        "createdBy" to "uidA",
        "createdAt" to T0,
        "memberNames" to mapOf("uidA" to "Ayesha", "uidB" to "Rafi"),
    )

    @Test fun `maps a complete pair`() {
        val p = pairFrom("pair1", raw)!!
        assertThat(p.id).isEqualTo("pair1")
        assertThat(p.members).containsExactly("uidA", "uidB").inOrder()
        assertThat(p.inviteCode).isEqualTo("K7M2QP")
        assertThat(p.isActive).isTrue()
    }

    @Test fun `finds the other member`() {
        val p = pairFrom("pair1", raw)!!
        assertThat(p.otherUid("uidA")).isEqualTo("uidB")
        assertThat(p.otherUid("uidB")).isEqualTo("uidA")
        assertThat(p.otherUid("stranger")).isEqualTo("uidA")
    }

    @Test fun `resolves the partner name from memberNames and falls back while the key is missing`() {
        // Plan amendment + addendum §M: the ONLY source is pairs/{id}.memberNames[otherUid].
        val p = pairFrom("pair1", raw)!!
        assertThat(p.partnerName("uidA")).isEqualTo("Rafi")
        assertThat(p.partnerName("uidB")).isEqualTo("Ayesha")

        // The other side has not registered a display name yet.
        val half = pairFrom("pair1", raw + mapOf("memberNames" to mapOf("uidA" to "Ayesha")))!!
        assertThat(half.partnerName("uidA")).isEqualTo("Your partner")

        // The map is absent entirely, or holds a blank name, or there is no other member.
        assertThat(pairFrom("pair1", raw - "memberNames")!!.partnerName("uidA")).isEqualTo("Your partner")
        assertThat(
            pairFrom("pair1", raw + mapOf("memberNames" to mapOf("uidB" to "   ")))!!.partnerName("uidA"),
        ).isEqualTo("Your partner")
        assertThat(
            pairFrom("pair1", raw + mapOf("members" to listOf("uidA")))!!.partnerName("uidA"),
        ).isEqualTo("Your partner")
    }

    @Test fun `a pending single-member pair is not active`() {
        val p = pairFrom("pair1", raw + mapOf("members" to listOf("uidA"), "status" to "pending"))!!
        assertThat(p.isActive).isFalse()
        assertThat(p.otherUid("uidA")).isNull()
    }

    @Test fun `a pair with no members is rejected`() {
        assertThat(pairFrom("pair1", raw - "members")).isNull()
    }
}

class SpotMapperTest {
    private val raw = mapOf<String, Any?>(
        "pairId" to "pair1",
        "name" to "Office",
        "lat" to 23.7808,
        "lng" to 90.4142,
        "radiusM" to 100L,
        "leadTimeMin" to 3L,
        "createdBy" to "uidB",
    )

    @Test fun `maps a complete spot`() {
        val s = spotFrom("spot1", raw)!!
        assertThat(s.id).isEqualTo("spot1")
        assertThat(s.name).isEqualTo("Office")
        assertThat(s.lat).isWithin(1e-9).of(23.7808)
        assertThat(s.radiusM).isEqualTo(100)
        assertThat(s.leadTimeMin).isEqualTo(3)
    }

    @Test fun `defaults radius to 100 m and lead time to 3 min`() {
        val s = spotFrom("spot1", raw - "radiusM" - "leadTimeMin")!!
        assertThat(s.radiusM).isEqualTo(100)
        assertThat(s.leadTimeMin).isEqualTo(3)
    }

    @Test fun `a spot without coordinates or a name is rejected`() {
        assertThat(spotFrom("spot1", raw - "lat")).isNull()
        assertThat(spotFrom("spot1", raw - "lng")).isNull()
        assertThat(spotFrom("spot1", raw - "name")).isNull()
    }
}

class TripMapperTest {
    private val raw = mapOf<String, Any?>(
        "pairId" to "pair1",
        "driverUid" to "uidA",
        "receiverUid" to "uidB",
        "spotId" to "spot1",
        "spot" to mapOf("lat" to 23.7808, "lng" to 90.4142, "radiusM" to 100L, "name" to "Office"),
        "leadTimeMin" to 3L,
        "state" to "driving",
        "startedAt" to T0,
        "eta" to mapOf("seconds" to 1080L, "updatedAt" to T0 + 60_000L, "approximate" to false),
        "bands" to mapOf("far" to 6600.0, "near" to 3850.0, "lead" to 2750.0),
        "phaseHint" to "far",
        // Both a top-level lastPos and one nested inside receiverView. Neither may survive
        // the mapper — addendum §H is enforced structurally, not by a comment in a screen.
        "lastPos" to mapOf("lat" to 23.79, "lng" to 90.40),
        "receiverView" to mapOf(
            "etaSeconds" to 1080L,
            "progressPct" to 53L,
            "lastPos" to mapOf("lat" to 23.78, "lng" to 90.41),
        ),
        "alerts" to mapOf(
            "started" to true, "tenMin" to false, "leadTime" to false,
            "arrived" to false, "didYouLeave" to false, "slipCount" to 0L,
        ),
        "routePolyline" to "_p~iF~ps|U",
    )

    @Test fun `maps a driving trip and drops every driver position`() {
        val t = tripFrom("trip1", raw)!!
        assertThat(t.id).isEqualTo("trip1")
        assertThat(t.state).isEqualTo("driving")
        assertThat(t.isDriving).isTrue()
        assertThat(t.spotName).isEqualTo("Office")
        assertThat(t.spotRadiusM).isEqualTo(100)
        assertThat(t.leadTimeMin).isEqualTo(3)
        assertThat(t.eta?.seconds).isEqualTo(1080)
        assertThat(t.bands?.near).isWithin(1e-9).of(3850.0)
        assertThat(t.phaseHint).isEqualTo("far")
        assertThat(t.alerts.started).isTrue()
        assertThat(t.alerts.leadTime).isFalse()
        assertThat(t.routePolyline).isEqualTo("_p~iF~ps|U")
        // Equality against the whole data class proves the model carries eta + progress
        // and NOTHING else, so no receiver surface can render a position by mistake.
        assertThat(t.receiverView).isEqualTo(ReceiverView(etaSeconds = 1080, progressPct = 53))
    }

    @Test fun `an armed trip has no eta or bands and is not driving`() {
        val t = tripFrom("trip1", raw - "eta" - "bands" - "startedAt" + mapOf("state" to "armed"))!!
        assertThat(t.isArmed).isTrue()
        assertThat(t.isDriving).isFalse()
        assertThat(t.eta).isNull()
        assertThat(t.bands).isNull()
        assertThat(t.startedAtMs).isNull()
    }

    @Test fun `role helpers read against a uid`() {
        val t = tripFrom("trip1", raw)!!
        assertThat(t.isDriver("uidA")).isTrue()
        assertThat(t.isDriver("uidB")).isFalse()
        assertThat(t.isReceiver("uidB")).isTrue()
    }

    @Test fun `missing alerts default to all false`() {
        val t = tripFrom("trip1", raw - "alerts")!!
        assertThat(t.alerts.started).isFalse()
        assertThat(t.alerts.slipCount).isEqualTo(0)
        // Addendum §I: a partially-populated alerts map must not trap either.
        val partial = tripFrom("trip1", raw + mapOf("alerts" to mapOf("started" to true)))!!
        assertThat(partial.alerts.started).isTrue()
        assertThat(partial.alerts.leadTime).isFalse()
        assertThat(partial.alerts.slipCount).isEqualTo(0)
    }

    @Test fun `a trip missing required identity fields is rejected`() {
        assertThat(tripFrom("trip1", raw - "driverUid")).isNull()
        assertThat(tripFrom("trip1", raw - "receiverUid")).isNull()
        assertThat(tripFrom("trip1", raw - "state")).isNull()
        assertThat(tripFrom("trip1", raw - "spot")).isNull()
    }
}

class ReplyMapperTest {
    @Test fun `maps a reply`() {
        val r = replyFrom("r1", mapOf("fromUid" to "uidB", "kind" to "fiveMore", "ts" to T0))!!
        assertThat(r.fromUid).isEqualTo("uidB")
        assertThat(r.kind).isEqualTo("fiveMore")
        assertThat(r.tsMs).isEqualTo(T0)
        assertThat(r.displayText).isEqualTo("5 more minutes please")
    }

    @Test fun `known kinds have canned text and custom uses its own`() {
        val table = listOf(
            "fiveMore" to "5 more minutes please",
            "takeYourTime" to "Take your time",
            "atSpot" to "I'm at the spot",
            // Not a client reply kind (addendum §B); the server may still record one.
            "runningLate" to "Running late",
        )
        for ((kind, expected) in table) {
            val r = replyFrom("r1", mapOf("fromUid" to "uidB", "kind" to kind, "ts" to T0))!!
            assertThat(r.displayText).isEqualTo(expected)
        }
        val custom = replyFrom("r1", mapOf("fromUid" to "uidB", "kind" to "custom", "text" to "on my way down", "ts" to T0))!!
        assertThat(custom.displayText).isEqualTo("on my way down")
    }

    @Test fun `a reply without a sender is rejected`() {
        assertThat(replyFrom("r1", mapOf("kind" to "fiveMore", "ts" to T0))).isNull()
    }
}
