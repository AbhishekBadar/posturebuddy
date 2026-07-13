import Foundation

/// Glues the motion source to the pure PostureEngine and publishes a snapshot
/// after every sample and timer tick. Never coalesces or deduplicates:
/// PostureMonitor's hysteresis needs every tick, and AppModel's
/// inequality-guarded writes are the SwiftUI rate limiter.
@MainActor
final class PostureTracker: ObservableObject {
    @Published private(set) var snapshot: PostureSnapshot

    /// Poor-posture threshold in degrees (negative; -5 strict, -35 relaxed).
    var threshold: Double {
        get { engine.threshold }
        set {
            engine.threshold = newValue
            publish()
        }
    }

    private let engine: PostureEngine
    private let source: MotionSource
    private var isRunning = false
    private var healthTimer: Timer?
    private var calibrationTimer: Timer?

    init(threshold: Double = PostureEngine.defaultThreshold,
         source: MotionSource = CMHeadphoneMotionSource()) {
        let engine = PostureEngine(threshold: threshold)
        self.engine = engine
        self.source = source
        self.snapshot = engine.snapshot
    }

    /// Starts motion updates and the connection health tick. Safe to call
    /// repeatedly; the tracker is never stopped — motion updates drive the
    /// menu-bar connection status even while nagging is paused.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        engine.start(at: Date())
        source.start(
            handler: { [weak self] pitchRadians, timestamp in
                Task { @MainActor [weak self] in
                    self?.receive(pitchRadians: pitchRadians, at: timestamp)
                }
            },
            errorHandler: { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.engine.noteError()
                    self.publish()
                }
            }
        )

        // .common mode: .default-mode timers stall during menu/slider event
        // tracking, which would freeze the connection status mid-drag.
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.engine.tick(at: Date())
                self.publish()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer

        publish()
    }

    // MARK: Calibration

    func beginCalibration() {
        start()
        engine.beginCalibration(at: Date())

        // 0.1 s tick drives phase progress even when no samples arrive
        // (the pause phase, or AirPods briefly out).
        calibrationTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.engine.tick(at: Date())
                self.publish()
                if case .done = self.snapshot.calibration {
                    self.calibrationTimer?.invalidate()
                    self.calibrationTimer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        calibrationTimer = timer

        publish()
    }

    func cancelCalibration() {
        calibrationTimer?.invalidate()
        calibrationTimer = nil
        engine.cancelCalibration()
        publish()
    }

    /// Applies and returns the calibrated threshold, or nil if calibration
    /// hasn't reached the done phase.
    func saveCalibration() -> Double? {
        calibrationTimer?.invalidate()
        calibrationTimer = nil
        guard let value = engine.saveCalibration() else { return nil }
        publish()
        return value
    }

    /// Sample entry point; internal so tests can drive it directly.
    func receive(pitchRadians: Double, at date: Date) {
        engine.ingest(pitchRadians: pitchRadians, at: date)
        publish()
    }

    private func publish() {
        snapshot = engine.snapshot
    }
}
