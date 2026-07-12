import XCTest
@testable import PostureBuddy

final class PostureEngineTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
    private func radians(_ degrees: Double) -> Double { degrees * .pi / 180.0 }

    // MARK: Validation, filter, quality

    func testRejectsNaNInfinityAndOutOfRangeSamples() {
        let engine = PostureEngine()
        engine.ingest(pitchRadians: Double.nan, at: at(0))
        engine.ingest(pitchRadians: Double.infinity, at: at(1))
        engine.ingest(pitchRadians: 4.0, at: at(2))   // > π
        engine.ingest(pitchRadians: -4.0, at: at(3))  // < -π
        XCTAssertEqual(engine.snapshot.pitchDegrees, 0.0, accuracy: 0.0001)
        XCTAssertEqual(engine.snapshot.quality, .good)
    }

    func testFirstSampleSeedsFilterDirectly() {
        let engine = PostureEngine()
        engine.ingest(pitchRadians: radians(-10), at: at(0))
        XCTAssertEqual(engine.snapshot.pitchDegrees, -10.0, accuracy: 0.0001)
    }

    func testFilterSmoothsSubsequentSamples() {
        let engine = PostureEngine()
        engine.ingest(pitchRadians: radians(-10), at: at(0))
        engine.ingest(pitchRadians: radians(-20), at: at(1))
        // EMA factor 0.4: -10 * 0.6 + -20 * 0.4 = -14
        XCTAssertEqual(engine.snapshot.pitchDegrees, -14.0, accuracy: 0.0001)
    }

    func testQualityFlipsOnThreshold() {
        let slouched = PostureEngine()                 // default threshold -22
        slouched.ingest(pitchRadians: radians(-30), at: at(0))
        XCTAssertEqual(slouched.snapshot.quality, .poor)

        let upright = PostureEngine()
        upright.ingest(pitchRadians: radians(-10), at: at(0))
        XCTAssertEqual(upright.snapshot.quality, .good)
    }

    func testCustomThresholdIsRespected() {
        let engine = PostureEngine(threshold: -10.0)
        engine.ingest(pitchRadians: radians(-15), at: at(0))
        XCTAssertEqual(engine.snapshot.quality, .poor)
    }
}
