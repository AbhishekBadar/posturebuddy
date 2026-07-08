import Foundation
import AirPostureCore

/// Persists PostureBuddy's user configuration in UserDefaults.
final class AppSettings {
    private let defaults: UserDefaults

    private enum Keys {
        static let threshold = "poorPostureThreshold"
        static let hasCalibrated = "hasCalibrated"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasCalibrated: Bool {
        get { defaults.bool(forKey: Keys.hasCalibrated) }
        set { defaults.set(newValue, forKey: Keys.hasCalibrated) }
    }

    var poorPostureThreshold: Double {
        get {
            defaults.object(forKey: Keys.threshold) as? Double
                ?? AirPostureConfiguration.default.poorPostureThreshold
        }
        set { defaults.set(newValue, forKey: Keys.threshold) }
    }
}
