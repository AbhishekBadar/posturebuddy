import Foundation

/// Applies sustained-slouch hysteresis to raw posture quality and publishes a PetState.
///
/// `.poor` must persist for `slouchGraceSeconds` before nagging; once nagging,
/// `.good` must persist for `recoverySeconds` before dismissing. Any non-connected
/// state or paused monitoring immediately hides the pet and clears timers.
@MainActor
final class PostureMonitor: ObservableObject {
    @Published private(set) var petState: PetState = .hidden

    var isMonitoring: Bool = true {
        didSet { if !isMonitoring { reset() } }
    }

    let slouchGraceSeconds: TimeInterval
    let recoverySeconds: TimeInterval

    private var poorSince: Date?
    private var goodSince: Date?

    init(slouchGraceSeconds: TimeInterval = 5.0, recoverySeconds: TimeInterval = 2.0) {
        self.slouchGraceSeconds = slouchGraceSeconds
        self.recoverySeconds = recoverySeconds
    }

    func ingest(quality: PostureQuality,
                connectionState: ConnectionPhase,
                at date: Date) {
        guard isMonitoring, connectionState == .connected else {
            reset()
            return
        }

        switch quality {
        case .poor:
            goodSince = nil
            if poorSince == nil { poorSince = date }
            if petState == .hidden,
               let start = poorSince,
               date.timeIntervalSince(start) >= slouchGraceSeconds {
                petState = .nagging
            }

        case .good:
            poorSince = nil
            if petState == .nagging {
                if goodSince == nil { goodSince = date }
                if let start = goodSince,
                   date.timeIntervalSince(start) >= recoverySeconds {
                    petState = .hidden
                    goodSince = nil
                }
            } else {
                goodSince = nil
            }
        }
    }

    private func reset() {
        poorSince = nil
        goodSince = nil
        if petState != .hidden { petState = .hidden }
    }
}
