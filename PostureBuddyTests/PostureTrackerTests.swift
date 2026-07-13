import XCTest
import Combine
@testable import PostureBuddy

@MainActor
final class PostureTrackerTests: XCTestCase {
    private final class FakeMotionSource: MotionSource {
        var isAvailable = true
        private(set) var startCount = 0
        func start(handler: @escaping (Double, Date) -> Void,
                   errorHandler: @escaping (Error) -> Void) {
            startCount += 1
        }
        func stop() {}
    }

    private func radians(_ degrees: Double) -> Double { degrees * .pi / 180.0 }

    func testStartIsIdempotentAndBeginsConnecting() {
        let source = FakeMotionSource()
        let tracker = PostureTracker(source: source)
        XCTAssertEqual(tracker.snapshot.connection, .disconnected)

        tracker.start()
        tracker.start()
        XCTAssertEqual(source.startCount, 1)
        XCTAssertEqual(tracker.snapshot.connection, .connecting)
    }

    func testReceiveConnectsAndClassifies() {
        let tracker = PostureTracker(source: FakeMotionSource())
        tracker.start()
        tracker.receive(pitchRadians: radians(-30), at: Date())
        XCTAssertEqual(tracker.snapshot.connection, .connected)
        XCTAssertEqual(tracker.snapshot.quality, .poor)  // -30 < default -22
    }

    func testEverySamplePublishesEvenWhenUnchanged() {
        // PostureMonitor's hysteresis timers advance per published tick, so the
        // tracker must never coalesce or deduplicate snapshots.
        let tracker = PostureTracker(source: FakeMotionSource())
        tracker.start()
        var publishCount = 0
        let cancellable = tracker.$snapshot.dropFirst().sink { _ in publishCount += 1 }
        defer { cancellable.cancel() }

        tracker.receive(pitchRadians: radians(-10), at: Date())
        tracker.receive(pitchRadians: radians(-10), at: Date())
        XCTAssertEqual(publishCount, 2)
    }

    func testThresholdWriteReclassifiesImmediately() {
        let tracker = PostureTracker(source: FakeMotionSource())
        tracker.start()
        tracker.receive(pitchRadians: radians(-15), at: Date())
        XCTAssertEqual(tracker.snapshot.quality, .good)   // -15 > -22

        tracker.threshold = -10.0
        XCTAssertEqual(tracker.snapshot.quality, .poor)   // -15 < -10
    }
}
