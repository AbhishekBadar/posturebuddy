import Foundation
import AirPostureCore

/// Persists PostureBuddy's user configuration in UserDefaults.
final class AppSettings {
    private let defaults: UserDefaults

    private enum Keys {
        static let threshold = "poorPostureThreshold"
        static let hasCalibrated = "hasCalibrated"
        static let soundEnabled = "soundEnabled"
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

    /// Whether the character's sound effect plays. Defaults to on.
    /// Read via `object(forKey:)` because `bool(forKey:)` reports `false` for an
    /// unset key, which would silently default the sound to off.
    var soundEnabled: Bool {
        get { defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.soundEnabled) }
    }
}
