package app.headstart.data

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.io.IOException

private const val T0 = 1_700_000_000_000L

private fun pos(ts: Long, lat: Double = 23.75) =
    PositionUpload(lat = lat, lng = 90.39, accuracyM = 10.0, speedMps = 12.0, ts = ts)

/** Records writes; refuses them while [online] is false, the way Firestore does when offline. */
private class FakeSink : PositionSink {
    var online = true
    val written = mutableListOf<PositionUpload>()
    var attempts = 0
    override suspend fun write(tripId: String, position: PositionUpload) {
        attempts++
        if (!online) throw IOException("offline")
        written += position
    }
}

class PositionUploaderTest {

    @Test fun `an online submit writes straight through and leaves nothing pending`() = runTest {
        val sink = FakeSink()
        val uploader = PositionUploader("trip1", sink)
        assertThat(uploader.submit(pos(T0))).isEqualTo(1)
        assertThat(sink.written.map { it.ts }).containsExactly(T0)
        assertThat(uploader.pending).isEqualTo(0)
    }

    @Test fun `offline submits buffer in order and nothing is written`() = runTest {
        val sink = FakeSink().apply { online = false }
        val uploader = PositionUploader("trip1", sink)
        uploader.submit(pos(T0))
        uploader.submit(pos(T0 + 5_000))
        uploader.submit(pos(T0 + 10_000))
        assertThat(sink.written).isEmpty()
        assertThat(uploader.pending).isEqualTo(3)
    }

    @Test fun `reconnecting replays oldest first`() = runTest {
        val sink = FakeSink().apply { online = false }
        val uploader = PositionUploader("trip1", sink)
        uploader.submit(pos(T0))
        uploader.submit(pos(T0 + 5_000))
        uploader.submit(pos(T0 + 10_000))
        sink.online = true
        assertThat(uploader.flush()).isEqualTo(3)
        assertThat(sink.written.map { it.ts }).containsExactly(T0, T0 + 5_000, T0 + 10_000).inOrder()
        assertThat(uploader.pending).isEqualTo(0)
    }

    @Test fun `a submit while buffered replays the backlog first, then the new fix`() = runTest {
        val sink = FakeSink().apply { online = false }
        val uploader = PositionUploader("trip1", sink)
        uploader.submit(pos(T0))
        uploader.submit(pos(T0 + 5_000))
        sink.online = true
        val sent = uploader.submit(pos(T0 + 10_000))
        assertThat(sent).isEqualTo(3)
        assertThat(sink.written.map { it.ts }).containsExactly(T0, T0 + 5_000, T0 + 10_000).inOrder()
    }

    @Test fun `the buffer is capped at 500 and drops the oldest`() = runTest {
        val sink = FakeSink().apply { online = false }
        val uploader = PositionUploader("trip1", sink)
        for (i in 0 until 620) uploader.submit(pos(T0 + i * 1_000L))
        assertThat(uploader.pending).isEqualTo(500)
        assertThat(uploader.dropped).isEqualTo(120)

        sink.online = true
        uploader.flush()
        assertThat(sink.written).hasSize(500)
        // The oldest 120 are gone; the surviving window starts at fix #120 and is in order.
        assertThat(sink.written.first().ts).isEqualTo(T0 + 120 * 1_000L)
        assertThat(sink.written.last().ts).isEqualTo(T0 + 619 * 1_000L)
        assertThat(sink.written.map { it.ts }).isInOrder()
    }

    @Test fun `the cap is configurable for tests without changing behaviour`() = runTest {
        val sink = FakeSink().apply { online = false }
        val uploader = PositionUploader("trip1", sink, maxBuffer = 3)
        for (i in 0 until 5) uploader.submit(pos(T0 + i * 1_000L))
        sink.online = true
        uploader.flush()
        assertThat(sink.written.map { it.ts })
            .containsExactly(T0 + 2_000L, T0 + 3_000L, T0 + 4_000L).inOrder()
    }

    @Test fun `a failure part way through a replay keeps the remainder in order`() = runTest {
        val sink = object : PositionSink {
            val written = mutableListOf<PositionUpload>()
            var failAfter = 2
            override suspend fun write(tripId: String, position: PositionUpload) {
                if (written.size >= failAfter) throw IOException("dropped mid-replay")
                written += position
            }
        }
        val uploader = PositionUploader("trip1", sink)
        uploader.submit(pos(T0))
        uploader.submit(pos(T0 + 1_000))
        uploader.submit(pos(T0 + 2_000))
        uploader.submit(pos(T0 + 3_000))
        assertThat(sink.written.map { it.ts }).containsExactly(T0, T0 + 1_000).inOrder()
        assertThat(uploader.pending).isEqualTo(2)

        sink.failAfter = 99
        assertThat(uploader.flush()).isEqualTo(2)
        assertThat(sink.written.map { it.ts })
            .containsExactly(T0, T0 + 1_000, T0 + 2_000, T0 + 3_000).inOrder()
    }

    @Test fun `flushing an empty buffer is a no-op that does not touch the sink`() = runTest {
        val sink = FakeSink()
        val uploader = PositionUploader("trip1", sink)
        assertThat(uploader.flush()).isEqualTo(0)
        assertThat(sink.attempts).isEqualTo(0)
    }

    @Test fun `the eta seconds field survives the round trip`() = runTest {
        val sink = FakeSink()
        val uploader = PositionUploader("trip1", sink)
        uploader.submit(pos(T0).copy(etaSec = 640))
        assertThat(sink.written.single().etaSec).isEqualTo(640)
    }
}
