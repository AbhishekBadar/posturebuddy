import XCTest
@testable import PostureBuddy

final class AppSettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "PostureBuddyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testThresholdDefaultsToCoreDefaultWhenUnset() {
        let settings = AppSettings(defaults: makeDefaults())
        XCTAssertEqual(settings.poorPostureThreshold,
                       PostureEngine.defaultThreshold,
                       accuracy: 0.0001)
        XCTAssertFalse(settings.hasCalibrated)
    }

    func testSoundEnabledDefaultsToTrueWhenUnset() {
        let settings = AppSettings(defaults: makeDefaults())
        XCTAssertTrue(settings.soundEnabled)
    }

    func testSoundEnabledPersistsWhenTurnedOff() {
        let defaults = makeDefaults()
        do {
            let settings = AppSettings(defaults: defaults)
            settings.soundEnabled = false
        }
        XCTAssertFalse(AppSettings(defaults: defaults).soundEnabled)
    }

    func testThresholdPersistsRoundTrip() {
        let defaults = makeDefaults()
        do {
            let settings = AppSettings(defaults: defaults)
            settings.poorPostureThreshold = -18.5
            settings.hasCalibrated = true
        }
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.poorPostureThreshold, -18.5, accuracy: 0.0001)
        XCTAssertTrue(reloaded.hasCalibrated)
    }
}
