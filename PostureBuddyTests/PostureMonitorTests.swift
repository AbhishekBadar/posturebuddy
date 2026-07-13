import XCTest
@testable import PostureBuddy

@MainActor
final class PostureMonitorTests: XCTestCase {
    private func makeMonitor() -> PostureMonitor {
        PostureMonitor(slouchGraceSeconds: 5.0, recoverySeconds: 2.0)
    }

    private func feed(_ monitor: PostureMonitor,
                      _ quality: PostureQuality,
                      at seconds: TimeInterval,
                      connection: ConnectionPhase = .connected) {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        monitor.ingest(quality: quality,
                       connectionState: connection,
                       at: base.addingTimeInterval(seconds))
    }

    func testStartsHidden() {
        XCTAssertEqual(makeMonitor().petState, .hidden)
    }

    func testBriefSlouchDoesNotNag() {
        let m = makeMonitor()
        feed(m, .poor, at: 0)
        feed(m, .poor, at: 3)      // only 3s < 5s grace
        feed(m, .good, at: 3.5)
        XCTAssertEqual(m.petState, .hidden)
    }

    func testSustainedSlouchNags() {
        let m = makeMonitor()
        feed(m, .poor, at: 0)
        feed(m, .poor, at: 4.9)
        XCTAssertEqual(m.petState, .hidden)
        feed(m, .poor, at: 5.0)    // reaches grace
        XCTAssertEqual(m.petState, .nagging)
    }

    func testRecoveryDismissesAfterSustainedGood() {
        let m = makeMonitor()
        feed(m, .poor, at: 0)
        feed(m, .poor, at: 5.0)    // nagging
        feed(m, .good, at: 6.0)    // 1s good < 2s recovery
        XCTAssertEqual(m.petState, .nagging)
        feed(m, .good, at: 8.0)    // 2s good → dismiss
        XCTAssertEqual(m.petState, .hidden)
    }

    func testPoorBlipDuringRecoveryRestartsRecoveryTimer() {
        let m = makeMonitor()
        feed(m, .poor, at: 0)
        feed(m, .poor, at: 5.0)    // nagging
        feed(m, .good, at: 6.0)    // recovery starts at 6.0
        feed(m, .poor, at: 6.5)    // poor interrupts; recovery clock must reset
        XCTAssertEqual(m.petState, .nagging)
        feed(m, .good, at: 7.0)    // recovery restarts at 7.0
        feed(m, .good, at: 8.5)    // 1.5s from 7.0 < 2s → still nagging (proves reset, not carry-over from 6.0)
        XCTAssertEqual(m.petState, .nagging)
        feed(m, .good, at: 9.0)    // 2.0s from 7.0 → dismiss
        XCTAssertEqual(m.petState, .hidden)
    }

    func testGoodBlipDuringSlouchResetsGraceTimer() {
        let m = makeMonitor()
        feed(m, .poor, at: 0)
        feed(m, .poor, at: 4.0)
        feed(m, .good, at: 4.2)    // resets poor timer
        feed(m, .poor, at: 4.4)    // grace restarts here
        feed(m, .poor, at: 8.0)    // 3.6s < 5s
        XCTAssertEqual(m.petState, .hidden)
        feed(m, .poor, at: 9.4)    // 5s from 4.4 → nag
        XCTAssertEqual(m.petState, .nagging)
    }

    func testDisconnectForcesHidden() {
        let m = makeMonitor()
        feed(m, .poor, at: 0)
        feed(m, .poor, at: 5.0)
        XCTAssertEqual(m.petState, .nagging)
        feed(m, .poor, at: 5.5, connection: .disconnected)
        XCTAssertEqual(m.petState, .hidden)
    }

    func testStopMonitoringForcesHidden() {
        let m = makeMonitor()
        feed(m, .poor, at: 0)
        feed(m, .poor, at: 5.0)
        XCTAssertEqual(m.petState, .nagging)
        m.isMonitoring = false
        XCTAssertEqual(m.petState, .hidden)
    }
}
