import Foundation

// MARK: - Snapshot types

enum PostureQuality: Equatable {
    case good
    case poor
}

enum ConnectionPhase: Equatable {
    case disconnected
    case connecting
    case connected
}

enum CalibrationPhase: Equatable {
    case idle
    case samplingUpright(progress: Double)
    case pause(progress: Double)
    case samplingSlouch(progress: Double)
    case done(threshold: Double)
}

struct PostureSnapshot: Equatable {
    let pitchDegrees: Double
    let quality: PostureQuality
    let connection: ConnectionPhase
    let calibration: CalibrationPhase
}

// MARK: - PostureEngine

/// Pure, time-injected posture engine: low-pass filters AirPods head pitch,
/// classifies posture quality against a threshold, tracks connection
/// freshness, and runs the guided calibration state machine.
///
/// No timers, no Combine, no CoreMotion — every state change happens inside
/// `ingest(pitchRadians:at:)` or `tick(at:)` with caller-supplied dates, so
/// all behavior is deterministically testable.
final class PostureEngine {
    static let defaultThreshold: Double = -22.0
    /// Valid threshold bounds in degrees: -5 is the strict end, -35 relaxed.
    static let thresholdRange: ClosedRange<Double> = -35.0 ... -5.0

    private static let filterFactor: Double = 0.4
    private static let staleInterval: TimeInterval = 5.0
    private static let disconnectInterval: TimeInterval = 10.0

    /// Poor-posture threshold in degrees; filtered pitch below it is a slouch.
    var threshold: Double

    private var filteredPitch: Double = 0.0
    private var hasSample = false
    private var isStarted = false
    private var lastSampleAt: Date = .distantPast
    private var connection: ConnectionPhase = .disconnected
    private var calibration: CalibrationPhase = .idle

    init(threshold: Double = PostureEngine.defaultThreshold) {
        self.threshold = threshold
    }

    var snapshot: PostureSnapshot {
        PostureSnapshot(
            pitchDegrees: filteredPitch,
            quality: filteredPitch < threshold ? .poor : .good,
            connection: connection,
            calibration: calibration
        )
    }

    /// Motion updates are starting; connection is pending until a sample arrives.
    func start(at date: Date) {
        isStarted = true
        lastSampleAt = date
        if connection != .connected {
            connection = .connecting
        }
    }

    /// Advances time-based state: connection staleness.
    func tick(at date: Date) {
        guard isStarted else { return }
        let silence = date.timeIntervalSince(lastSampleAt)
        if silence >= Self.disconnectInterval {
            connection = .disconnected
        } else if silence >= Self.staleInterval {
            connection = .connecting
        }
    }

    /// The motion provider reported a failure.
    func noteError() {
        connection = .disconnected
    }

    func ingest(pitchRadians: Double, at date: Date) {
        guard pitchRadians.isFinite,
              (-Double.pi ... Double.pi).contains(pitchRadians) else { return }

        let pitchDegrees = pitchRadians * 180.0 / .pi
        filteredPitch = hasSample
            ? filteredPitch * (1.0 - Self.filterFactor) + pitchDegrees * Self.filterFactor
            : pitchDegrees
        hasSample = true
        lastSampleAt = date
        connection = .connected
    }
}
