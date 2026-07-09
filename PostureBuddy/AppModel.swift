import Foundation
import Combine
import SwiftUI
import AirPostureCore

/// Central coordinator: wires the AirPostureCore tracker to the PostureMonitor
/// and the pet overlay, and exposes menu-bar state.
@MainActor
final class AppModel: ObservableObject {
    let tracker: AirPostureTracker
    let monitor: PostureMonitor
    let settings: AppSettings

    @Published var isMonitoring: Bool = true
    @Published private(set) var connectionState: AirPostureConnectionState = .disconnected
    @Published private(set) var calibrationState: AirPostureCalibrationState = .idle
    @Published var threshold: Double
    @Published var isSoundEnabled: Bool

    /// Threshold slider bounds (degrees). More negative = more tolerant of head tilt.
    let thresholdRange: ClosedRange<Double> = -35.0 ... -5.0

    private let overlay = PetOverlayWindowController()
    private var nagMessages = NagMessages()
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        self.isSoundEnabled = settings.soundEnabled

        var config = AirPostureConfiguration.default
        config.poorPostureThreshold = settings.poorPostureThreshold
        // PostureBuddy never reads pitchHistory; a 1-element history avoids the
        // per-sample copy-on-write of a 50-element buffer inside the core.
        config.pitchHistorySize = 1
        let tracker = AirPostureTracker(configuration: config)
        self.tracker = tracker
        self.monitor = PostureMonitor()
        self.threshold = config.poorPostureThreshold

        // Snapshot → connection/calibration state + monitor ingest.
        //
        // No receive(on:): the tracker is @MainActor and already publishes on the
        // main thread — a scheduler hop would only add latency (and RunLoop.main
        // stalls delivery during UI event tracking, e.g. slider drags).
        //
        // The snapshot arrives at sensor rate (~25-40 Hz). ingest must run on
        // every tick to advance the hysteresis timers, but the @Published
        // properties are only written on real changes — @Published fires
        // objectWillChange on every write, and this model drives the MenuBarExtra
        // scene, so unconditional writes would re-evaluate SwiftUI ~40x/s forever.
        tracker.$snapshot
            .sink { [weak self] snapshot in
                guard let self else { return }
                if self.connectionState != snapshot.connectionState {
                    self.connectionState = snapshot.connectionState
                }
                if self.calibrationState != snapshot.calibrationState {
                    self.calibrationState = snapshot.calibrationState
                }
                self.monitor.ingest(quality: snapshot.quality,
                                    connectionState: snapshot.connectionState,
                                    at: Date())
            }
            .store(in: &cancellables)

        // PetState → overlay.
        monitor.$petState
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .nagging:
                    self.overlay.show(message: self.nagMessages.next(),
                                      playSound: self.isSoundEnabled)
                case .hidden:
                    self.overlay.hide()
                }
            }
            .store(in: &cancellables)

        tracker.startMotionUpdates()
    }

    var statusText: String {
        switch connectionState {
        case .connected:    return "AirPods connected"
        case .connecting:   return "Connecting to AirPods…"
        case .reconnecting: return "Reconnecting…"
        case .error:        return "AirPods error"
        case .disconnected: return "AirPods not connected"
        }
    }

    var menuBarSymbol: String {
        connectionState == .connected ? "figure.seated.side" : "airpods"
    }

    func setMonitoring(_ on: Bool) {
        isMonitoring = on
        monitor.isMonitoring = on
        if on {
            tracker.startMotionUpdates()
        } else {
            overlay.hide()
        }
    }

    func setSoundEnabled(_ on: Bool) {
        isSoundEnabled = on
        settings.soundEnabled = on
    }

    func applyThreshold(_ value: Double) {
        let clamped = min(max(value, thresholdRange.lowerBound), thresholdRange.upperBound)
        threshold = clamped
        tracker.configuration.poorPostureThreshold = clamped
        settings.poorPostureThreshold = clamped
    }

    // MARK: Calibration (driven by Task 6's CalibrationView)

    func startCalibration() {
        monitor.isMonitoring = false
        overlay.hide()
        tracker.beginCalibration()
    }

    func saveCalibration() {
        if tracker.saveCalibrationResult() != nil {
            // saveCalibrationResult() has written the raw computed threshold into
            // tracker.configuration; clamp + persist it consistently via applyThreshold.
            applyThreshold(tracker.configuration.poorPostureThreshold)
            settings.hasCalibrated = true
        }
        monitor.isMonitoring = isMonitoring
    }

    func cancelCalibration() {
        tracker.cancelCalibration()
        monitor.isMonitoring = isMonitoring
    }
}
