import XCTest
import AirPostureCore
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
                       AirPostureConfiguration.default.poorPostureThreshold,
                       accuracy: 0.0001)
        XCTAssertFalse(settings.hasCalibrated)
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
