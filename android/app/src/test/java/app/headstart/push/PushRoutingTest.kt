package app.headstart.push

import com.google.common.truth.Truth.assertThat
import org.junit.Test

/**
 * Which channel a push lands on is a product decision with a one-line implementation and a
 * large blast radius — `leadTime` on the quiet channel means the person misses their ride.
 * It is pure logic, so it is tested. These assertions run against exactly the code the FCM
 * service and the debug injector both call.
 */
class PushRoutingTest {

    private val allKinds = listOf(
        "started", "tenMin", "leadTime", "slip", "arrived", "lost", "timeout",
        "cancelled", "didYouLeave", "armed", "noShow", "runningLate", "reply",
    )

    @Test fun `only leadTime is urgent`() {
        assertThat(channelFor("leadTime")).isEqualTo(CHANNEL_URGENT)
        assertThat(renderSpec(mapOf("kind" to "leadTime")).urgent).isTrue()

        // Addendum C: `arrived` is NOT urgent, the backend plan doc was wrong.
        val quiet = allKinds - "leadTime"
        assertThat(quiet).hasSize(12)
        for (kind in quiet) {
            assertThat(channelFor(kind)).isEqualTo(CHANNEL_UPDATES)
            assertThat(renderSpec(mapOf("kind" to kind)).channelId).isEqualTo(CHANNEL_UPDATES)
            assertThat(renderSpec(mapOf("kind" to kind)).urgent).isFalse()
        }
        // The contract's full kind set, and nothing invented on top of it.
        assertThat(PUSH_KINDS).containsExactlyElementsIn(allKinds).inOrder()
    }

    @Test fun `an unknown kind falls back to the quiet channel`() {
        assertThat(channelFor("somethingNew")).isEqualTo(CHANNEL_UPDATES)
        assertThat(channelFor(null)).isEqualTo(CHANNEL_UPDATES)
        assertThat(channelFor("")).isEqualTo(CHANNEL_UPDATES)
        // A push with no kind at all still renders somewhere quiet rather than crashing.
        val spec = renderSpec(emptyMap())
        assertThat(spec.kind).isNull()
        assertThat(spec.channelId).isEqualTo(CHANNEL_UPDATES)
        assertThat(spec.urgent).isFalse()
    }

    @Test fun `every kind gets a stable notification id so updates replace, not stack`() {
        // Same kind twice -> same id; different kinds -> different ids.
        assertThat(notificationIdFor("tenMin")).isEqualTo(notificationIdFor("tenMin"))
        assertThat(notificationIdFor("tenMin")).isNotEqualTo(notificationIdFor("leadTime"))
        // ...and none of them collides with the ongoing trip notification.
        for (kind in allKinds) {
            assertThat(notificationIdFor(kind)).isNotEqualTo(ONGOING_TRIP_ID)
            assertThat(renderSpec(mapOf("kind" to kind)).notificationId)
                .isEqualTo(notificationIdFor(kind))
        }
        assertThat(allKinds.map { notificationIdFor(it) }.toSet()).hasSize(allKinds.size)
        // Unknown kinds share one bucket, still clear of the ongoing id.
        assertThat(notificationIdFor("somethingNew")).isEqualTo(notificationIdFor(null))
        assertThat(notificationIdFor("somethingNew")).isNotEqualTo(ONGOING_TRIP_ID)
        assertThat(allKinds.map { notificationIdFor(it) }).doesNotContain(notificationIdFor(null))
    }

    @Test fun `didYouLeave is the only kind that raises the in-app sheet`() {
        assertThat(raisesNudgeSheet("didYouLeave")).isTrue()
        assertThat(renderSpec(mapOf("kind" to "didYouLeave")).raisesNudgeSheet).isTrue()
        for (kind in allKinds - "didYouLeave") {
            assertThat(raisesNudgeSheet(kind)).isFalse()
        }
        assertThat(raisesNudgeSheet(null)).isFalse()
    }

    @Test fun `trip-ending kinds tell the app to stop tracking`() {
        for (kind in listOf("arrived", "cancelled", "timeout")) {
            assertThat(endsTracking(kind)).isTrue()
            assertThat(renderSpec(mapOf("kind" to kind)).endsTracking).isTrue()
        }
        for (kind in listOf("started", "tenMin", "leadTime", "slip", "lost", "reply")) {
            assertThat(endsTracking(kind)).isFalse()
        }
        // Addendum D: trip-scoped pushes carry data.tripId; non-trip pushes omit it.
        assertThat(renderSpec(mapOf("kind" to "arrived", "tripId" to "t1")).tripId).isEqualTo("t1")
        assertThat(renderSpec(mapOf("kind" to "reply")).tripId).isNull()
        // Title and body survive the trip through the shared renderer.
        val spec = renderSpec(mapOf("kind" to "leadTime", "title" to "Start walking now", "body" to "Alex is 3 min away"))
        assertThat(spec.title).isEqualTo("Start walking now")
        assertThat(spec.body).isEqualTo("Alex is 3 min away")
        assertThat(spec.hasText).isTrue()
        assertThat(renderSpec(mapOf("kind" to "armed")).hasText).isFalse()
    }
}
