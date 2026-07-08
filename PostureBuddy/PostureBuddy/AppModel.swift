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

    /// Threshold slider bounds (degrees). More negative = more tolerant of head tilt.
    let thresholdRange: ClosedRange<Double> = -35.0 ... -5.0

    private let overlay = PetOverlayWindowController()
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings

        var config = AirPostureConfiguration.default
        config.poorPostureThreshold = settings.poorPostureThreshold
        let tracker = AirPostureTracker(configuration: config)
        self.tracker = tracker
        self.monitor = PostureMonitor()
        self.threshold = config.poorPostureThreshold

        // Snapshot → connection/calibration state + monitor ingest.
        tracker.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.connectionState = snapshot.connectionState
                self.calibrationState = snapshot.calibrationState
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
                case .nagging: self.overlay.show(message: "Sit up straight!")
                case .hidden:  self.overlay.hide()
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
        if let config = tracker.saveCalibrationResult() {
            threshold = config.poorPostureThreshold
            settings.poorPostureThreshold = config.poorPostureThreshold
            settings.hasCalibrated = true
        }
        monitor.isMonitoring = isMonitoring
    }

    func cancelCalibration() {
        tracker.cancelCalibration()
        monitor.isMonitoring = isMonitoring
    }
}
