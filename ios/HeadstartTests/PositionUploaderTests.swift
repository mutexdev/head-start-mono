// ios/HeadstartTests/PositionUploaderTests.swift
import XCTest
@testable import Headstart

private let T0: Int64 = 1_700_000_000_000

private func pos(_ ts: Int64, lat: Double = 23.75) -> PositionUpload {
    PositionUpload(lat: lat, lng: 90.39, accuracyM: 10, speedMps: 12, ts: ts, etaSec: nil)
}

private struct SinkError: Error {}

/// Records writes; refuses them while `online` is false, the way Firestore's
/// callable path does when the device has no route to the internet.
private actor FakeSink: PositionSink {
    private(set) var online: Bool
    private(set) var written: [PositionUpload] = []
    private(set) var attempts = 0
    /// Refuse once `written.count >= failAfter`.
    private var failAfter = Int.max

    init(online: Bool = true) { self.online = online }

    func setOnline(_ value: Bool) { online = value }
    func setFailAfter(_ value: Int) { failAfter = value }
    var timestamps: [Int64] { written.map(\.ts) }

    func write(tripId: String, position: PositionUpload) async throws {
        attempts += 1
        if !online || written.count >= failAfter { throw SinkError() }
        written.append(position)
    }
}

final class PositionUploaderTests: XCTestCase {

    func testAnOnlineSubmitWritesStraightThroughAndLeavesNothingPending() async {
        let sink = FakeSink()
        let uploader = PositionUploader(tripId: "trip1", sink: sink)
        let sent = await uploader.submit(pos(T0))
        XCTAssertEqual(sent, 1)
        await XCTAssertEqualAsync(await sink.timestamps, [T0])
        await XCTAssertEqualAsync(await uploader.pending, 0)
    }

    func testOfflineSubmitsBufferInOrderAndNothingIsWritten() async {
        let sink = FakeSink(online: false)
        let uploader = PositionUploader(tripId: "trip1", sink: sink)
        await uploader.submit(pos(T0))
        await uploader.submit(pos(T0 + 5_000))
        await uploader.submit(pos(T0 + 10_000))
        await XCTAssertEqualAsync(await sink.timestamps, [])
        await XCTAssertEqualAsync(await uploader.pending, 3)
    }

    func testReconnectingReplaysOldestFirst() async {
        let sink = FakeSink(online: false)
        let uploader = PositionUploader(tripId: "trip1", sink: sink)
        await uploader.submit(pos(T0))
        await uploader.submit(pos(T0 + 5_000))
        await uploader.submit(pos(T0 + 10_000))
        await sink.setOnline(true)
        let sent = await uploader.flush()
        XCTAssertEqual(sent, 3)
        await XCTAssertEqualAsync(await sink.timestamps, [T0, T0 + 5_000, T0 + 10_000])
        await XCTAssertEqualAsync(await uploader.pending, 0)
    }

    func testASubmitWhileBufferedReplaysTheBacklogFirstThenTheNewFix() async {
        let sink = FakeSink(online: false)
        let uploader = PositionUploader(tripId: "trip1", sink: sink)
        await uploader.submit(pos(T0))
        await uploader.submit(pos(T0 + 5_000))
        await sink.setOnline(true)
        let sent = await uploader.submit(pos(T0 + 10_000))
        XCTAssertEqual(sent, 3)
        await XCTAssertEqualAsync(await sink.timestamps, [T0, T0 + 5_000, T0 + 10_000])
    }

    func testTheBufferIsCappedAtFiveHundredAndDropsTheOldest() async {
        let sink = FakeSink(online: false)
        let uploader = PositionUploader(tripId: "trip1", sink: sink)
        for i in 0..<620 { await uploader.submit(pos(T0 + Int64(i) * 1_000)) }
        await XCTAssertEqualAsync(await uploader.pending, 500)
        await XCTAssertEqualAsync(await uploader.dropped, 120)

        await sink.setOnline(true)
        await uploader.flush()
        let stamps = await sink.timestamps
        XCTAssertEqual(stamps.count, 500)
        // The oldest 120 are gone; the surviving window starts at fix #120 and is in order.
        XCTAssertEqual(stamps.first, T0 + 120 * 1_000)
        XCTAssertEqual(stamps.last, T0 + 619 * 1_000)
        XCTAssertEqual(stamps, stamps.sorted())
    }

    func testTheCapIsConfigurableForTestsWithoutChangingBehaviour() async {
        let sink = FakeSink(online: false)
        let uploader = PositionUploader(tripId: "trip1", sink: sink, maxBuffer: 3)
        for i in 0..<5 { await uploader.submit(pos(T0 + Int64(i) * 1_000)) }
        await sink.setOnline(true)
        await uploader.flush()
        await XCTAssertEqualAsync(
            await sink.timestamps,
            [T0 + 2_000, T0 + 3_000, T0 + 4_000]
        )
    }

    func testAFailurePartWayThroughAReplayKeepsTheRemainderInOrder() async {
        let sink = FakeSink()
        await sink.setFailAfter(2)
        let uploader = PositionUploader(tripId: "trip1", sink: sink)
        await uploader.submit(pos(T0))
        await uploader.submit(pos(T0 + 1_000))
        await uploader.submit(pos(T0 + 2_000))
        await uploader.submit(pos(T0 + 3_000))
        await XCTAssertEqualAsync(await sink.timestamps, [T0, T0 + 1_000])
        await XCTAssertEqualAsync(await uploader.pending, 2)

        await sink.setFailAfter(Int.max)
        let sent = await uploader.flush()
        XCTAssertEqual(sent, 2)
        await XCTAssertEqualAsync(
            await sink.timestamps,
            [T0, T0 + 1_000, T0 + 2_000, T0 + 3_000]
        )
    }

    func testFlushingAnEmptyBufferIsANoOpThatDoesNotTouchTheSink() async {
        let sink = FakeSink()
        let uploader = PositionUploader(tripId: "trip1", sink: sink)
        let sent = await uploader.flush()
        XCTAssertEqual(sent, 0)
        await XCTAssertEqualAsync(await sink.attempts, 0)
    }

    func testTheEtaSecondsFieldSurvivesTheRoundTrip() async {
        let sink = FakeSink()
        let uploader = PositionUploader(tripId: "trip1", sink: sink)
        var p = pos(T0)
        p.etaSec = 640
        await uploader.submit(p)
        let written = await sink.written
        XCTAssertEqual(written.first?.etaSec, 640)
    }

    func testAFixIsBuiltFromALocationFixAndTheOnDeviceEta() {
        let fix = LocationFix(lat: 23.75, lng: 90.39, accuracyM: 8.5, speedMps: 11.2, tsMs: T0)
        let p = PositionUpload(fix: fix, etaSec: 640)
        XCTAssertEqual(p.lat, 23.75)
        XCTAssertEqual(p.lng, 90.39)
        XCTAssertEqual(p.accuracyM, 8.5)
        XCTAssertEqual(p.speedMps, 11.2)
        XCTAssertEqual(p.ts, T0)
        XCTAssertEqual(p.etaSec, 640)
        // The uploader never sends a negative speed; CoreLocation reports -1 when unknown.
        let unknownSpeed = LocationFix(lat: 1, lng: 1, accuracyM: 5, speedMps: -1, tsMs: T0)
        XCTAssertEqual(PositionUpload(fix: unknownSpeed, etaSec: nil).speedMps, 0)
    }
}

/// XCTAssertEqual does not accept `await` in its autoclosure, so unwrap first.
private func XCTAssertEqualAsync<T: Equatable>(
    _ actual: T,
    _ expected: T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    XCTAssertEqual(actual, expected, file: file, line: line)
}
