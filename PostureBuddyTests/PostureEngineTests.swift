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

    // MARK: Connection lifecycle

    func testStartMovesDisconnectedToConnecting() {
        let engine = PostureEngine()
        XCTAssertEqual(engine.snapshot.connection, .disconnected)
        engine.start(at: at(0))
        XCTAssertEqual(engine.snapshot.connection, .connecting)
    }

    func testFirstSampleConnects() {
        let engine = PostureEngine()
        engine.start(at: at(0))
        engine.ingest(pitchRadians: radians(-10), at: at(1))
        XCTAssertEqual(engine.snapshot.connection, .connected)
    }

    func testSampleSilenceDegradesConnectionThenSampleRecovers() {
        let engine = PostureEngine()
        engine.start(at: at(0))
        engine.ingest(pitchRadians: radians(-10), at: at(1))

        engine.tick(at: at(3))     // 2 s silence: still connected
        XCTAssertEqual(engine.snapshot.connection, .connected)

        engine.tick(at: at(6.5))   // 5.5 s silence: stale
        XCTAssertEqual(engine.snapshot.connection, .connecting)

        engine.tick(at: at(11.5))  // 10.5 s silence: gone
        XCTAssertEqual(engine.snapshot.connection, .disconnected)

        engine.ingest(pitchRadians: radians(-10), at: at(12))
        XCTAssertEqual(engine.snapshot.connection, .connected)
    }

    func testTickBeforeStartKeepsDisconnected() {
        let engine = PostureEngine()
        engine.tick(at: at(60))
        XCTAssertEqual(engine.snapshot.connection, .disconnected)
    }

    func testInvalidSampleDoesNotRefreshConnection() {
        let engine = PostureEngine()
        engine.start(at: at(0))
        engine.ingest(pitchRadians: radians(-10), at: at(1))
        engine.ingest(pitchRadians: Double.nan, at: at(8))  // must not count
        engine.tick(at: at(8))                              // 7 s since last valid
        XCTAssertEqual(engine.snapshot.connection, .connecting)
    }

    func testErrorForcesDisconnected() {
        let engine = PostureEngine()
        engine.start(at: at(0))
        engine.ingest(pitchRadians: radians(-10), at: at(1))
        engine.noteError()
        XCTAssertEqual(engine.snapshot.connection, .disconnected)
    }

    // MARK: Calibration

    /// Runs begin → upright samples → pause → slouch samples → done.
    /// uprightDegrees/slouchDegrees are the constant pitch fed in each phase.
    private func calibrate(_ engine: PostureEngine,
                           uprightDegrees: Double,
                           slouchDegrees: Double) {
        engine.beginCalibration(at: at(0))
        engine.ingest(pitchRadians: radians(uprightDegrees), at: at(1))
        engine.ingest(pitchRadians: radians(uprightDegrees), at: at(2))
        engine.tick(at: at(5))     // upright done → pause
        engine.tick(at: at(8))     // pause done → samplingSlouch
        engine.ingest(pitchRadians: radians(slouchDegrees), at: at(9))
        engine.ingest(pitchRadians: radians(slouchDegrees), at: at(10))
        engine.tick(at: at(13))    // slouch done → done(threshold:)
    }

    func testCalibrationWalkthroughPhasesAndProgress() {
        let engine = PostureEngine()
        engine.start(at: at(0))
        engine.beginCalibration(at: at(0))
        XCTAssertEqual(engine.snapshot.calibration, .samplingUpright(progress: 0.0))

        engine.tick(at: at(2.5))
        XCTAssertEqual(engine.snapshot.calibration, .samplingUpright(progress: 0.5))

        engine.ingest(pitchRadians: radians(-5), at: at(3))
        engine.tick(at: at(5))
        XCTAssertEqual(engine.snapshot.calibration, .pause(progress: 0.0))

        engine.tick(at: at(6.5))
        XCTAssertEqual(engine.snapshot.calibration, .pause(progress: 0.5))

        engine.tick(at: at(8))
        XCTAssertEqual(engine.snapshot.calibration, .samplingSlouch(progress: 0.0))

        engine.ingest(pitchRadians: radians(-25), at: at(9))
        engine.tick(at: at(13))
        // Midpoint of -5 and -25 = -15.
        XCTAssertEqual(engine.snapshot.calibration, .done(threshold: -15.0))
    }

    func testCalibrationClampsToStrictBound() {
        let engine = PostureEngine()
        engine.start(at: at(0))
        calibrate(engine, uprightDegrees: 20, slouchDegrees: 10)  // midpoint +15
        XCTAssertEqual(engine.snapshot.calibration, .done(threshold: -5.0))
    }

    func testCalibrationClampsToRelaxedBound() {
        let engine = PostureEngine()
        engine.start(at: at(0))
        calibrate(engine, uprightDegrees: -45, slouchDegrees: -65)  // midpoint -55
        XCTAssertEqual(engine.snapshot.calibration, .done(threshold: -35.0))
    }

    func testCancelCalibrationReturnsToIdleWithoutChangingThreshold() {
        let engine = PostureEngine()
        engine.start(at: at(0))
        engine.beginCalibration(at: at(0))
        engine.tick(at: at(2))
        engine.cancelCalibration()
        XCTAssertEqual(engine.snapshot.calibration, .idle)
        XCTAssertEqual(engine.threshold, PostureEngine.defaultThreshold, accuracy: 0.0001)
    }

    func testSaveCalibrationAppliesAndReturnsThreshold() {
        let engine = PostureEngine()
        engine.start(at: at(0))
        XCTAssertNil(engine.saveCalibration())  // nothing to save yet

        calibrate(engine, uprightDegrees: -5, slouchDegrees: -25)
        XCTAssertEqual(engine.saveCalibration() ?? .nan, -15.0, accuracy: 0.0001)
        XCTAssertEqual(engine.threshold, -15.0, accuracy: 0.0001)
        XCTAssertEqual(engine.snapshot.calibration, .idle)
    }
}
