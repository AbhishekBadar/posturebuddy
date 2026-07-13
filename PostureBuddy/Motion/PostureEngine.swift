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
    private static let samplingDuration: TimeInterval = 5.0
    private static let pauseDuration: TimeInterval = 3.0

    /// Poor-posture threshold in degrees; filtered pitch below it is a slouch.
    var threshold: Double

    private var filteredPitch: Double = 0.0
    private var hasSample = false
    private var isStarted = false
    private var lastSampleAt: Date = .distantPast
    private var connection: ConnectionPhase = .disconnected
    private var calibration: CalibrationPhase = .idle
    private var phaseStartedAt: Date?
    private var phaseSamples: [Double] = []
    private var uprightAverage: Double = 0.0

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

    /// Advances time-based state: connection staleness and calibration progress.
    func tick(at date: Date) {
        guard isStarted else { return }
        let silence = date.timeIntervalSince(lastSampleAt)
        if silence >= Self.disconnectInterval {
            connection = .disconnected
        } else if silence >= Self.staleInterval {
            connection = .connecting
        }
        advanceCalibration(at: date)
    }

    /// The motion provider reported a failure.
    func noteError() {
        connection = .disconnected
    }

    // MARK: Calibration

    func beginCalibration(at date: Date) {
        phaseSamples.removeAll()
        uprightAverage = 0.0
        calibration = .samplingUpright(progress: 0.0)
        phaseStartedAt = date
    }

    func cancelCalibration() {
        calibration = .idle
        phaseStartedAt = nil
        phaseSamples.removeAll()
    }

    /// Applies and returns the calibrated threshold, or nil if calibration
    /// hasn't reached `.done`.
    func saveCalibration() -> Double? {
        guard case .done(let value) = calibration else { return nil }
        threshold = value
        calibration = .idle
        return value
    }

    private func advanceCalibration(at date: Date) {
        guard let phaseStart = phaseStartedAt else { return }
        let elapsed = date.timeIntervalSince(phaseStart)

        switch calibration {
        case .samplingUpright:
            if elapsed >= Self.samplingDuration {
                uprightAverage = average(of: phaseSamples)
                phaseSamples.removeAll()
                calibration = .pause(progress: 0.0)
                phaseStartedAt = date
            } else {
                calibration = .samplingUpright(progress: elapsed / Self.samplingDuration)
            }
        case .pause:
            if elapsed >= Self.pauseDuration {
                calibration = .samplingSlouch(progress: 0.0)
                phaseStartedAt = date
            } else {
                calibration = .pause(progress: elapsed / Self.pauseDuration)
            }
        case .samplingSlouch:
            if elapsed >= Self.samplingDuration {
                let midpoint = (uprightAverage + average(of: phaseSamples)) / 2.0
                let clamped = min(max(midpoint, Self.thresholdRange.lowerBound),
                                  Self.thresholdRange.upperBound)
                calibration = .done(threshold: clamped)
                phaseStartedAt = nil
                phaseSamples.removeAll()
            } else {
                calibration = .samplingSlouch(progress: elapsed / Self.samplingDuration)
            }
        case .idle, .done:
            phaseStartedAt = nil
        }
    }

    private func average(of values: [Double]) -> Double {
        values.isEmpty ? 0.0 : values.reduce(0, +) / Double(values.count)
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

        switch calibration {
        case .samplingUpright, .samplingSlouch:
            phaseSamples.append(pitchDegrees)
        default:
            break
        }
    }
}
