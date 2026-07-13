import Foundation
import Combine
import SwiftUI

/// Central coordinator: wires the posture tracker to the PostureMonitor
/// and the pet overlay, and exposes menu-bar state.
@MainActor
final class AppModel: ObservableObject {
    let tracker: PostureTracker
    let monitor: PostureMonitor
    let settings: AppSettings

    @Published var isMonitoring: Bool = true
    @Published private(set) var connectionState: ConnectionPhase = .disconnected
    @Published private(set) var calibrationState: CalibrationPhase = .idle
    @Published var threshold: Double
    @Published var isSoundEnabled: Bool

    /// Threshold slider bounds (degrees). More negative = more tolerant of head tilt.
    let thresholdRange: ClosedRange<Double> = PostureEngine.thresholdRange

    private let overlay = PetOverlayWindowController()
    private var nagMessages = NagMessages()
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        self.isSoundEnabled = settings.soundEnabled

        let tracker = PostureTracker(threshold: settings.poorPostureThreshold)
        self.tracker = tracker
        self.monitor = PostureMonitor()
        self.threshold = tracker.threshold

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
                if self.connectionState != snapshot.connection {
                    self.connectionState = snapshot.connection
                }
                if self.calibrationState != snapshot.calibration {
                    self.calibrationState = snapshot.calibration
                }
                self.monitor.ingest(quality: snapshot.quality,
                                    connectionState: snapshot.connection,
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

        tracker.start()
    }

    var statusText: String {
        switch connectionState {
        case .connected:    return "AirPods connected"
        case .connecting:   return "Connecting to AirPods…"
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
            tracker.start()
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
        tracker.threshold = clamped
        settings.poorPostureThreshold = clamped
    }

    // MARK: Calibration (driven by CalibrationView)

    func startCalibration() {
        monitor.isMonitoring = false
        overlay.hide()
        tracker.beginCalibration()
    }

    func saveCalibration() {
        if let value = tracker.saveCalibration() {
            // The engine already clamps; route through applyThreshold anyway so
            // clamping + persistence stay consistent in one place.
            applyThreshold(value)
            settings.hasCalibrated = true
        }
        monitor.isMonitoring = isMonitoring
    }

    func cancelCalibration() {
        tracker.cancelCalibration()
        monitor.isMonitoring = isMonitoring
    }
}
