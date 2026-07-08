# PostureBuddy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu-bar app that detects poor posture via AirPods head-tracking and shows an animated corner "pet" that nags the user to sit up straight, dismissing automatically once posture is corrected.

**Architecture:** A SwiftUI `MenuBarExtra` app reuses the existing `AirPostureCore` Swift package (referenced by relative path) for AirPods motion + posture classification. An `AppModel` subscribes to the tracker's `snapshot`, feeds quality/connection into a `PostureMonitor` that applies sustained-slouch hysteresis and emits a `PetState`, which drives a borderless non-activating `NSPanel` overlay hosting a SwiftUI pet. A guided calibration window personalizes the posture threshold, persisted in `UserDefaults`.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit (`NSPanel`), Combine, `AirPostureCore` (local SPM package), XcodeGen, XCTest, macOS 14+.

## Global Constraints

- **Platform:** macOS 14.0 deployment target. AppKit + SwiftUI. Language Swift 5.9.
- **Dependency reuse:** Reference `AirPostureCore` as a local SPM package by relative path `../AirPosture/AirPostureCore`. Do **not** modify that package.
- **Detection:** AirPods head tracking only (via `AirPostureCore`). No webcam, no ARKit.
- **Graphic:** a corner pet character with a speech bubble ("Sit up straight!"). Non-blocking, never steals focus.
- **Timing defaults:** pet appears after `slouchGraceSeconds = 5.0` of sustained `.poor`; auto-dismisses after `recoverySeconds = 2.0` of sustained `.good` (hysteresis).
- **Calibration:** first-run guided flow (`sit up straight` → `slouch`) via `AirPostureTracker.beginCalibration()` / `saveCalibrationResult()`; threshold adjustable via a sensitivity slider afterward.
- **Art:** placeholder graphics using SF Symbols (no binary sprite assets yet).
- **New folder:** `PostureBuddy/` at repo root (PascalCase, matching sibling `AirPosture/`).
- **Commit messages:** do NOT include a `Co-Authored-By` trailer.
- **Build system:** XcodeGen `project.yml` is the source of truth; `AirPosture.xcodeproj`-style generated project. Run `xcodegen generate` after editing `project.yml`.

## Key `AirPostureCore` API (verified — reused, not modified)

```swift
@MainActor public final class AirPostureTracker: ObservableObject {
    @Published public private(set) var snapshot: AirPostureSnapshot
    public var configuration: AirPostureConfiguration
    public init(configuration: AirPostureConfiguration = .default,
                provider: HeadphoneMotionProvider = CMHeadphoneMotionProvider())
    public func startMotionUpdates()
    public func stopMotionUpdates()
    public func beginCalibration()
    public func cancelCalibration()
    public func saveCalibrationResult() -> AirPostureConfiguration?   // sets configuration.poorPostureThreshold
}

public struct AirPostureSnapshot: Codable, Equatable {
    public let quality: AirPostureQuality              // .good / .poor
    public let adjustedPitchDegrees: Double
    public let connectionState: AirPostureConnectionState  // .disconnected/.connecting/.connected/.reconnecting/.error
    public let calibrationState: AirPostureCalibrationState
    // ...plus sample, goodPosturePercent, pitchHistory, sessionSnapshot
    public static let initial: AirPostureSnapshot
}

public enum AirPostureQuality: String, Codable, Equatable { case good, poor }
public enum AirPostureConnectionState: String, Codable, Equatable { case disconnected, connecting, connected, reconnecting, error }

public struct AirPostureConfiguration: Codable, Equatable {
    public var poorPostureThreshold: Double  // default -22.0
    public static let `default`: AirPostureConfiguration
}

public enum AirPostureCalibrationState: Codable, Equatable {
    case idle
    case recordingGoodPosture(progress: Double)
    case transition(progress: Double)
    case recordingBadPosture(progress: Double)
    case complete(goodPostureAverage: Double, badPostureAverage: Double, calculatedThreshold: Double)
}

// For tests / simulating motion:
public final class MockHeadphoneMotionProvider: HeadphoneMotionProvider {
    public init(isDeviceMotionAvailable: Bool = true)
    public func emit(pitchRadians: Double, rollRadians: Double = 0, yawRadians: Double = 0, timestamp: Date = Date())
    public func emit(error: Error)
}
```

## File Structure

```
PostureBuddy/
├── project.yml                              # XcodeGen: app + test targets, AirPostureCore package
├── .gitignore                               # ignore generated .xcodeproj, DerivedData
├── README.md                                # what it is, build/run, art-swap note
├── PostureBuddy/
│   ├── Info.plist                           # LSUIElement=true (menu-bar only), motion usage
│   ├── PostureBuddyApp.swift                # @main App: MenuBarExtra + calibration Window
│   ├── AppModel.swift                       # wires tracker ↔ monitor ↔ overlay ↔ settings
│   ├── PostureMonitor.swift                 # sustained-slouch hysteresis → PetState  (UNIT TESTED)
│   ├── PetState.swift                       # enum PetState { hidden, nagging }
│   ├── AppSettings.swift                    # UserDefaults persistence  (UNIT TESTED)
│   ├── PetOverlayWindowController.swift      # borderless non-activating NSPanel, bottom-right
│   ├── PetView.swift                        # SwiftUI pet + speech bubble + slide animation
│   ├── MenuBarContentView.swift             # status, monitoring toggle, sensitivity, recalibrate, quit
│   └── CalibrationView.swift                # guided calibration UI
└── PostureBuddyTests/
    ├── PostureMonitorTests.swift            # hysteresis/timing assertions
    └── AppSettingsTests.swift               # persistence round-trip
```

Note on testability: `PostureMonitor` and `AppSettings` are pure, injectable, and unit-tested. UI/window code (`PetOverlayWindowController`, `PetView`, `MenuBarContentView`, `CalibrationView`, `AppModel` wiring) is verified by building and running the app manually — those tasks list explicit manual verification steps instead of XCTest steps.

---

### Task 1: Project scaffold — buildable menu-bar app shell

**Files:**
- Create: `PostureBuddy/project.yml`
- Create: `PostureBuddy/.gitignore`
- Create: `PostureBuddy/PostureBuddy/Info.plist`
- Create: `PostureBuddy/PostureBuddy/PostureBuddyApp.swift`

**Interfaces:**
- Consumes: `AirPostureCore` package at `../AirPosture/AirPostureCore`.
- Produces: a runnable app named `PostureBuddy` with a `MenuBarExtra` icon; scheme `PostureBuddy`; a `PostureBuddyTests` unit-test target.

- [ ] **Step 1: Ensure XcodeGen is available**

Run: `which xcodegen || brew install xcodegen`
Expected: a path to `xcodegen`, or Homebrew installs it.

- [ ] **Step 2: Create `PostureBuddy/project.yml`**

```yaml
name: PostureBuddy
options:
  bundleIdPrefix: com.example
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true

packages:
  AirPostureCore:
    path: ../AirPosture/AirPostureCore

targets:
  PostureBuddy:
    type: application
    platform: macOS
    sources:
      - PostureBuddy
    dependencies:
      - package: AirPostureCore
    info:
      path: PostureBuddy/Info.plist
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.posturebuddy
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        SWIFT_VERSION: "5.9"
        GENERATE_INFOPLIST_FILE: NO
        ENABLE_HARDENED_RUNTIME: YES

  PostureBuddyTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - PostureBuddyTests
    dependencies:
      - target: PostureBuddy
      - package: AirPostureCore
    settings:
      base:
        SWIFT_VERSION: "5.9"

schemes:
  PostureBuddy:
    build:
      targets:
        PostureBuddy: all
        PostureBuddyTests: [test]
    run:
      config: Debug
    test:
      targets:
        - PostureBuddyTests
```

- [ ] **Step 3: Create `PostureBuddy/.gitignore`**

```gitignore
*.xcodeproj/
DerivedData/
.build/
*.xcuserstate
```

- [ ] **Step 4: Create `PostureBuddy/PostureBuddy/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>PostureBuddy</string>
	<key>CFBundleIdentifier</key>
	<string>com.example.posturebuddy</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSMotionUsageDescription</key>
	<string>PostureBuddy reads AirPods head motion to detect slouching.</string>
</dict>
</plist>
```

- [ ] **Step 5: Create `PostureBuddy/PostureBuddy/PostureBuddyApp.swift` (minimal shell)**

```swift
import SwiftUI

@main
struct PostureBuddyApp: App {
    var body: some Scene {
        MenuBarExtra("PostureBuddy", systemImage: "figure.seated.side") {
            Text("PostureBuddy")
            Divider()
            Button("Quit PostureBuddy") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 6: Generate the Xcode project**

Run: `cd PostureBuddy && xcodegen generate`
Expected: `Created project at .../PostureBuddy/PostureBuddy.xcodeproj`

- [ ] **Step 7: Build**

Run: `cd PostureBuddy && xcodebuild -scheme PostureBuddy -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Manual verification**

Run the app (from Xcode Run, or `open` the built `.app` under DerivedData). Expected: a person-seated icon appears in the macOS menu bar; clicking it shows a small window with "PostureBuddy" and a working "Quit PostureBuddy" button. No Dock icon (LSUIElement).

- [ ] **Step 9: Commit**

```bash
cd /Users/abhishek/Projects/experiments/posturebuddy
git add PostureBuddy/project.yml PostureBuddy/.gitignore PostureBuddy/PostureBuddy/Info.plist PostureBuddy/PostureBuddy/PostureBuddyApp.swift
git commit -m "feat(posturebuddy): scaffold menu-bar app shell with AirPostureCore dependency"
```

---

### Task 2: `AppSettings` — persist calibrated threshold (TDD)

**Files:**
- Create: `PostureBuddy/PostureBuddy/AppSettings.swift`
- Test: `PostureBuddy/PostureBuddyTests/AppSettingsTests.swift`

**Interfaces:**
- Consumes: `AirPostureConfiguration.default` (from `AirPostureCore`).
- Produces:
  ```swift
  final class AppSettings {
      init(defaults: UserDefaults = .standard)
      var hasCalibrated: Bool { get set }
      var poorPostureThreshold: Double { get set }   // defaults to AirPostureConfiguration.default.poorPostureThreshold (-22.0) when unset
  }
  ```

- [ ] **Step 1: Write the failing test**

Create `PostureBuddy/PostureBuddyTests/AppSettingsTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd PostureBuddy && xcodebuild test -scheme PostureBuddy -destination 'platform=macOS' -only-testing:PostureBuddyTests/AppSettingsTests`
Expected: FAIL — compile error, `cannot find 'AppSettings' in scope`.

- [ ] **Step 3: Write the minimal implementation**

Create `PostureBuddy/PostureBuddy/AppSettings.swift`:

```swift
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
```

- [ ] **Step 4: Regenerate project (new source file) and run the test**

Run: `cd PostureBuddy && xcodegen generate && xcodebuild test -scheme PostureBuddy -destination 'platform=macOS' -only-testing:PostureBuddyTests/AppSettingsTests`
Expected: `** TEST SUCCEEDED **` (both tests pass).

- [ ] **Step 5: Commit**

```bash
cd /Users/abhishek/Projects/experiments/posturebuddy
git add PostureBuddy/PostureBuddy/AppSettings.swift PostureBuddy/PostureBuddyTests/AppSettingsTests.swift
git commit -m "feat(posturebuddy): add AppSettings threshold persistence"
```

---

### Task 3: `PetState` + `PostureMonitor` — sustained-slouch hysteresis (TDD)

**Files:**
- Create: `PostureBuddy/PostureBuddy/PetState.swift`
- Create: `PostureBuddy/PostureBuddy/PostureMonitor.swift`
- Test: `PostureBuddy/PostureBuddyTests/PostureMonitorTests.swift`

**Interfaces:**
- Consumes: `AirPostureQuality`, `AirPostureConnectionState` (from `AirPostureCore`).
- Produces:
  ```swift
  enum PetState: Equatable { case hidden, nagging }

  @MainActor final class PostureMonitor: ObservableObject {
      @Published private(set) var petState: PetState   // starts .hidden
      var isMonitoring: Bool                            // setting false resets to .hidden
      let slouchGraceSeconds: TimeInterval
      let recoverySeconds: TimeInterval
      init(slouchGraceSeconds: TimeInterval = 5.0, recoverySeconds: TimeInterval = 2.0)
      func ingest(quality: AirPostureQuality, connectionState: AirPostureConnectionState, at date: Date)
  }
  ```
- Contract (drives Task 5 wiring): the app calls `ingest` on every `snapshot` update with `Date()`. `.poor` sustained ≥ `slouchGraceSeconds` → `.nagging`; then `.good` sustained ≥ `recoverySeconds` → `.hidden`. Any non-`.connected` state or `isMonitoring == false` forces `.hidden` and clears timers.

- [ ] **Step 1: Write the failing tests**

Create `PostureBuddy/PostureBuddyTests/PostureMonitorTests.swift`:

```swift
import XCTest
import AirPostureCore
@testable import PostureBuddy

@MainActor
final class PostureMonitorTests: XCTestCase {
    private func makeMonitor() -> PostureMonitor {
        PostureMonitor(slouchGraceSeconds: 5.0, recoverySeconds: 2.0)
    }

    private func feed(_ monitor: PostureMonitor,
                      _ quality: AirPostureQuality,
                      at seconds: TimeInterval,
                      connection: AirPostureConnectionState = .connected) {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        monitor.ingest(quality: quality,
                       connectionState: connection,
                       at: base.addingTimeInterval(seconds))
    }

    func testStartsHidden() {
        XCTAssertEqual(makeMonitor().petState, .hidden)
    }

    func testBriefSlouchDoesNotNag() {
        let m = makeMonitor()
        feed(m, .poor, at: 0)
        feed(m, .poor, at: 3)      // only 3s < 5s grace
        feed(m, .good, at: 3.5)
        XCTAssertEqual(m.petState, .hidden)
    }

    func testSustainedSlouchNags() {
        let m = makeMonitor()
        feed(m, .poor, at: 0)
        feed(m, .poor, at: 4.9)
        XCTAssertEqual(m.petState, .hidden)
        feed(m, .poor, at: 5.0)    // reaches grace
        XCTAssertEqual(m.petState, .nagging)
    }

    func testRecoveryDismissesAfterSustainedGood() {
        let m = makeMonitor()
        feed(m, .poor, at: 0)
        feed(m, .poor, at: 5.0)    // nagging
        feed(m, .good, at: 6.0)    // 1s good < 2s recovery
        XCTAssertEqual(m.petState, .nagging)
        feed(m, .good, at: 8.0)    // 2s good → dismiss
        XCTAssertEqual(m.petState, .hidden)
    }

    func testGoodBlipDuringSlouchResetsGraceTimer() {
        let m = makeMonitor()
        feed(m, .poor, at: 0)
        feed(m, .poor, at: 4.0)
        feed(m, .good, at: 4.2)    // resets poor timer
        feed(m, .poor, at: 4.4)    // grace restarts here
        feed(m, .poor, at: 8.0)    // 3.6s < 5s
        XCTAssertEqual(m.petState, .hidden)
        feed(m, .poor, at: 9.4)    // 5s from 4.4 → nag
        XCTAssertEqual(m.petState, .nagging)
    }

    func testDisconnectForcesHidden() {
        let m = makeMonitor()
        feed(m, .poor, at: 0)
        feed(m, .poor, at: 5.0)
        XCTAssertEqual(m.petState, .nagging)
        feed(m, .poor, at: 5.5, connection: .disconnected)
        XCTAssertEqual(m.petState, .hidden)
    }

    func testStopMonitoringForcesHidden() {
        let m = makeMonitor()
        feed(m, .poor, at: 0)
        feed(m, .poor, at: 5.0)
        XCTAssertEqual(m.petState, .nagging)
        m.isMonitoring = false
        XCTAssertEqual(m.petState, .hidden)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd PostureBuddy && xcodegen generate && xcodebuild test -scheme PostureBuddy -destination 'platform=macOS' -only-testing:PostureBuddyTests/PostureMonitorTests`
Expected: FAIL — `cannot find 'PostureMonitor' in scope`.

- [ ] **Step 3: Create `PostureBuddy/PostureBuddy/PetState.swift`**

```swift
/// Whether the posture pet should be on screen.
enum PetState: Equatable {
    case hidden
    case nagging
}
```

- [ ] **Step 4: Create `PostureBuddy/PostureBuddy/PostureMonitor.swift`**

```swift
import Foundation
import AirPostureCore

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

    func ingest(quality: AirPostureQuality,
                connectionState: AirPostureConnectionState,
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
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd PostureBuddy && xcodegen generate && xcodebuild test -scheme PostureBuddy -destination 'platform=macOS' -only-testing:PostureBuddyTests/PostureMonitorTests`
Expected: `** TEST SUCCEEDED **` (all 7 tests pass).

- [ ] **Step 6: Commit**

```bash
cd /Users/abhishek/Projects/experiments/posturebuddy
git add PostureBuddy/PostureBuddy/PetState.swift PostureBuddy/PostureBuddy/PostureMonitor.swift PostureBuddy/PostureBuddyTests/PostureMonitorTests.swift
git commit -m "feat(posturebuddy): add PostureMonitor sustained-slouch hysteresis"
```

---

### Task 4: Pet overlay — `PetView` + `PetOverlayWindowController`

**Files:**
- Create: `PostureBuddy/PostureBuddy/PetView.swift`
- Create: `PostureBuddy/PostureBuddy/PetOverlayWindowController.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks (pure UI).
- Produces:
  ```swift
  struct PetView: View { init(message: String) }

  @MainActor final class PetOverlayWindowController {
      func show(message: String)   // creates/positions bottom-right panel, animates pet in
      func hide()                  // animates pet out, then orders panel out
  }
  ```
- Contract (drives Task 5): `AppModel` calls `show(message:)` on `.nagging` and `hide()` on `.hidden`.

- [ ] **Step 1: Create `PostureBuddy/PostureBuddy/PetView.swift`**

```swift
import SwiftUI

/// The posture pet: a speech bubble + placeholder SF Symbol character that
/// slides in from the right. `isPresented` drives the slide/fade transition.
struct PetView: View {
    let message: String
    @Binding var isPresented: Bool

    init(message: String, isPresented: Binding<Bool> = .constant(true)) {
        self.message = message
        self._isPresented = isPresented
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            SpeechBubble(text: message)
            Image(systemName: "figure.seated.side.air.distribution.middle")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
                .padding(16)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.orange.opacity(0.4), lineWidth: 2))
        }
        .padding(16)
        .offset(x: isPresented ? 0 : 260)
        .opacity(isPresented ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.72), value: isPresented)
    }
}

private struct SpeechBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.orange.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }
}

#Preview {
    PetView(message: "Sit up straight!")
        .frame(width: 220, height: 200)
        .padding()
}
```

Note: if `figure.seated.side.air.distribution.middle` is unavailable on the toolchain, substitute `figure.seated.side` (guaranteed on macOS 14). Verify the symbol renders in the `#Preview` before wiring.

- [ ] **Step 2: Create `PostureBuddy/PostureBuddy/PetOverlayWindowController.swift`**

```swift
import AppKit
import SwiftUI

/// Manages a borderless, transparent, non-activating NSPanel pinned to the
/// bottom-right of the active screen. Hosts a PetView and never steals focus.
@MainActor
final class PetOverlayWindowController {
    private var panel: NSPanel?
    private var isPresented = false
    private let size = NSSize(width: 240, height: 220)
    private let margin: CGFloat = 24

    func show(message: String) {
        let panel = ensurePanel()
        isPresented = true
        panel.contentView = NSHostingView(
            rootView: PetView(message: message, isPresented: .constant(true))
        )
        reposition()
        panel.orderFrontRegardless()
    }

    func hide() {
        guard let panel, isPresented else { return }
        isPresented = false
        // Slide out, then remove from screen.
        panel.contentView = NSHostingView(
            rootView: PetView(message: "", isPresented: .constant(false))
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, !self.isPresented else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.panel = panel
        return panel
    }

    private func reposition() {
        guard let panel, let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let origin = NSPoint(x: vf.maxX - size.width - margin,
                             y: vf.minY + margin)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
```

- [ ] **Step 3: Regenerate & build**

Run: `cd PostureBuddy && xcodegen generate && xcodebuild -scheme PostureBuddy -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verification (temporary harness)**

Temporarily add to `PostureBuddyApp.swift`'s menu a `Button("Test pet") { ... }` that instantiates a `PetOverlayWindowController`, calls `show(message: "Sit up straight!")`, and a second button calling `hide()`. Run the app, click Test pet. Expected: the pet slides in at the bottom-right corner over other apps, does not steal focus (the frontmost app keeps its focus ring), and slides out on hide. Remove the temporary buttons afterward (Task 5 provides the real wiring).

- [ ] **Step 5: Commit**

```bash
cd /Users/abhishek/Projects/experiments/posturebuddy
git add PostureBuddy/PostureBuddy/PetView.swift PostureBuddy/PostureBuddy/PetOverlayWindowController.swift
git commit -m "feat(posturebuddy): add pet overlay panel and view"
```

---

### Task 5: `AppModel` wiring + menu-bar UI

**Files:**
- Create: `PostureBuddy/PostureBuddy/AppModel.swift`
- Create: `PostureBuddy/PostureBuddy/MenuBarContentView.swift`
- Modify: `PostureBuddy/PostureBuddy/PostureBuddyApp.swift`

**Interfaces:**
- Consumes: `AirPostureTracker`, `AirPostureConfiguration`, `AirPostureConnectionState`, `AirPostureCalibrationState` (core); `PostureMonitor`, `PetState`, `AppSettings`, `PetOverlayWindowController` (earlier tasks).
- Produces:
  ```swift
  @MainActor final class AppModel: ObservableObject {
      let tracker: AirPostureTracker
      let monitor: PostureMonitor
      let settings: AppSettings
      @Published var isMonitoring: Bool
      @Published private(set) var connectionState: AirPostureConnectionState
      @Published private(set) var calibrationState: AirPostureCalibrationState
      @Published var threshold: Double
      init(settings: AppSettings = AppSettings())
      func setMonitoring(_ on: Bool)
      func applyThreshold(_ value: Double)
      func startCalibration()          // used by Task 6
      func saveCalibration()           // used by Task 6
      func cancelCalibration()         // used by Task 6
  }
  ```

- [ ] **Step 1: Create `PostureBuddy/PostureBuddy/AppModel.swift`**

```swift
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
```

- [ ] **Step 2: Create `PostureBuddy/PostureBuddy/MenuBarContentView.swift`**

```swift
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.statusText,
                  systemImage: model.connectionState == .connected ? "checkmark.circle.fill" : "airpods")
                .font(.headline)

            Divider()

            Toggle("Monitor my posture", isOn: Binding(
                get: { model.isMonitoring },
                set: { model.setMonitoring($0) }
            ))

            VStack(alignment: .leading, spacing: 4) {
                Text("Sensitivity")
                    .font(.subheadline)
                Slider(
                    value: Binding(get: { model.threshold },
                                   set: { model.applyThreshold($0) }),
                    in: model.thresholdRange
                ) {
                    Text("Sensitivity")
                } minimumValueLabel: {
                    Text("Strict")
                } maximumValueLabel: {
                    Text("Relaxed")
                }
                Text("Threshold: \(Int(model.threshold))° head tilt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Recalibrate…") {
                model.startCalibration()
                openWindow(id: "calibration")
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("Quit PostureBuddy") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}
```

- [ ] **Step 3: Replace `PostureBuddy/PostureBuddy/PostureBuddyApp.swift`**

```swift
import SwiftUI

@main
struct PostureBuddyApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("PostureBuddy", systemImage: model.menuBarSymbol) {
            MenuBarContentView(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Calibrate PostureBuddy", id: "calibration") {
            CalibrationView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
```

Note: this references `CalibrationView`, created in Task 6. To keep this task independently buildable, also create a temporary stub now and replace it in Task 6:

Create `PostureBuddy/PostureBuddy/CalibrationView.swift` (stub — replaced in Task 6):

```swift
import SwiftUI

struct CalibrationView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Text("Calibration coming soon")
            .frame(width: 360, height: 240)
    }
}
```

- [ ] **Step 4: Regenerate & build**

Run: `cd PostureBuddy && xcodegen generate && xcodebuild -scheme PostureBuddy -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run full unit test suite (guard against regressions)**

Run: `cd PostureBuddy && xcodebuild test -scheme PostureBuddy -destination 'platform=macOS'`
Expected: `** TEST SUCCEEDED **` (AppSettings + PostureMonitor suites).

- [ ] **Step 6: Manual verification (with AirPods)**

Put on supported AirPods. Run the app. Expected:
- Menu shows "AirPods connected" once head tracking starts.
- Slouch (tilt head down past threshold) and hold ~5s → pet slides in bottom-right with "Sit up straight!".
- Sit up straight and hold ~2s → pet slides out.
- Toggle "Monitor my posture" off → pet hides and stays hidden while slouching.
- Drag the Sensitivity slider toward "Strict" → nagging triggers at a smaller tilt.

If AirPods aren't available, confirm the menu shows "AirPods not connected" and no pet appears.

- [ ] **Step 7: Commit**

```bash
cd /Users/abhishek/Projects/experiments/posturebuddy
git add PostureBuddy/PostureBuddy/AppModel.swift PostureBuddy/PostureBuddy/MenuBarContentView.swift PostureBuddy/PostureBuddy/PostureBuddyApp.swift PostureBuddy/PostureBuddy/CalibrationView.swift
git commit -m "feat(posturebuddy): wire tracker, monitor, overlay and menu-bar UI"
```

---

### Task 6: Guided calibration flow

**Files:**
- Modify (replace stub): `PostureBuddy/PostureBuddy/CalibrationView.swift`

**Interfaces:**
- Consumes: `AppModel.startCalibration()`, `AppModel.saveCalibration()`, `AppModel.cancelCalibration()`, `AppModel.calibrationState` (`AirPostureCalibrationState`).
- Produces: a full calibration window UI.

- [ ] **Step 1: Replace `PostureBuddy/PostureBuddy/CalibrationView.swift`**

```swift
import SwiftUI
import AirPostureCore

/// Guided calibration: records good posture, then bad posture, then lets the
/// user save the computed threshold. State comes from AppModel.calibrationState,
/// which mirrors the tracker's AirPostureCalibrationState.
struct CalibrationView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Posture Calibration")
                .font(.title2.bold())

            instruction
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            progressView

            controls
        }
        .padding(28)
        .frame(width: 380)
    }

    @ViewBuilder
    private var instruction: some View {
        switch model.calibrationState {
        case .idle:
            Text("We'll measure your good and slouched posture to personalize your threshold. Keep your AirPods in.")
        case .recordingGoodPosture:
            Text("Sit up straight and hold still…")
                .font(.headline)
        case .transition:
            Text("Great! Now get ready to slouch…")
                .font(.headline)
        case .recordingBadPosture:
            Text("Now slouch the way you normally do…")
                .font(.headline)
        case .complete(_, _, let threshold):
            Text("Done! Your personalized threshold is \(Int(threshold))°.")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var progressView: some View {
        switch model.calibrationState {
        case .recordingGoodPosture(let p), .transition(let p), .recordingBadPosture(let p):
            ProgressView(value: p)
                .progressViewStyle(.linear)
                .frame(width: 260)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch model.calibrationState {
        case .idle:
            HStack {
                Button("Cancel") { dismiss() }
                Button("Start") { model.startCalibration() }
                    .keyboardShortcut(.defaultAction)
            }
        case .recordingGoodPosture, .transition, .recordingBadPosture:
            Button("Cancel") {
                model.cancelCalibration()
                dismiss()
            }
        case .complete:
            HStack {
                Button("Discard") {
                    model.cancelCalibration()
                    dismiss()
                }
                Button("Save") {
                    model.saveCalibration()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
```

Note: `AppModel.startCalibration()` is already called by the menu's "Recalibrate…" button before the window opens, so the window may open mid-recording. The `Start` button here is for the idle/first-run path (opening the window without pre-starting). Both paths converge because the UI is driven purely by `calibrationState`.

- [ ] **Step 2: Regenerate & build**

Run: `cd PostureBuddy && xcodegen generate && xcodebuild -scheme PostureBuddy -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual verification (with AirPods)**

Run the app → menu → "Recalibrate…". Expected:
- Window opens; it walks through "Sit up straight" (progress bar) → "get ready to slouch" → "Now slouch" (progress bar) → "Done! threshold N°".
- Click Save → window closes; the menu's Sensitivity threshold now reads the calibrated value; slouch/recovery nagging respects the new threshold.
- Re-open and Cancel mid-way → calibration aborts, previous threshold retained, monitoring resumes.

- [ ] **Step 4: Commit**

```bash
cd /Users/abhishek/Projects/experiments/posturebuddy
git add PostureBuddy/PostureBuddy/CalibrationView.swift
git commit -m "feat(posturebuddy): add guided calibration window"
```

---

### Task 7: README and first-run calibration prompt

**Files:**
- Create: `PostureBuddy/README.md`
- Modify: `PostureBuddy/PostureBuddy/PostureBuddyApp.swift`

**Interfaces:**
- Consumes: `AppModel.settings.hasCalibrated`.
- Produces: docs + a first-run nudge to calibrate.

- [ ] **Step 1: Add first-run calibration prompt**

In `PostureBuddyApp.swift`, open the calibration window automatically on first launch when the user has never calibrated. Replace the `MenuBarExtra { ... }` scene's modifier chain by adding an `.onAppear`-style hook via a small wrapper. Concretely, update the body:

```swift
import SwiftUI

@main
struct PostureBuddyApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("PostureBuddy", systemImage: model.menuBarSymbol) {
            MenuBarContentView(model: model)
                .task {
                    if !model.settings.hasCalibrated {
                        openWindow(id: "calibration")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
        }
        .menuBarExtraStyle(.window)

        Window("Calibrate PostureBuddy", id: "calibration") {
            CalibrationView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
```

Note: `.task` on the menu content runs when the menu is first rendered. If a purely-automatic open at launch is desired instead, this is acceptable for v0.1 — the first-run window opens the first time the user opens the menu. Do not over-engineer this.

- [ ] **Step 2: Create `PostureBuddy/README.md`**

```markdown
# PostureBuddy

A macOS menu-bar app that watches your posture through your AirPods and sends a
friendly pet to nag you when you slouch.

## How it works

PostureBuddy reuses the **AirPostureCore** engine (from the sibling `AirPosture`
project) to read AirPods head-tilt via `CMHeadphoneMotionManager`. When your head
stays tilted past your calibrated threshold for ~5 seconds, an animated pet slides
into the bottom-right corner of your screen and asks you to sit up straight. It
walks off automatically once you've held good posture for a couple of seconds.

## Requirements

- macOS 14+
- AirPods with head tracking (AirPods Pro, AirPods 3rd gen+, AirPods Max, or
  compatible Beats)
- Xcode 16+, XcodeGen (`brew install xcodegen`)

## Build & run

```bash
cd PostureBuddy
xcodegen generate
open PostureBuddy.xcodeproj   # then Run, or:
xcodebuild -scheme PostureBuddy -destination 'platform=macOS' build
```

## Test

```bash
cd PostureBuddy
xcodebuild test -scheme PostureBuddy -destination 'platform=macOS'
```

## Menu

- **Monitor my posture** — pause/resume nagging
- **Sensitivity** — adjust the head-tilt threshold (Strict ↔ Relaxed)
- **Recalibrate…** — re-run the guided good/slouch calibration
- **Quit**

## Notes

- The pet uses **placeholder SF Symbol art**. Swap `PetView.swift`'s `Image` for
  real sprites when available.
- `AirPostureCore` is referenced by relative path (`../AirPosture/AirPostureCore`);
  keep the sibling project alongside this folder.
- Depends on nothing over the network; no analytics.
```

- [ ] **Step 3: Regenerate, build, and run the full test suite**

Run: `cd PostureBuddy && xcodegen generate && xcodebuild -scheme PostureBuddy -destination 'platform=macOS' build && xcodebuild test -scheme PostureBuddy -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **`.

- [ ] **Step 4: Manual verification**

Delete the app's preferences to simulate first run:
`defaults delete com.example.posturebuddy 2>/dev/null || true`
Run the app and open the menu. Expected: the calibration window appears on first interaction; after saving, subsequent launches do not force it open.

- [ ] **Step 5: Commit**

```bash
cd /Users/abhishek/Projects/experiments/posturebuddy
git add PostureBuddy/README.md PostureBuddy/PostureBuddy/PostureBuddyApp.swift
git commit -m "docs(posturebuddy): add README and first-run calibration prompt"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Menu-bar app reusing AirPostureCore → Tasks 1, 5. ✓
- AirPods head-tracking detection → AirPostureCore via `AppModel`, Task 5. ✓
- Corner pet with speech bubble → Tasks 4, 5. ✓
- Sustained-slouch appear + auto-dismiss (hysteresis) → Task 3. ✓
- Guided calibration + adjustable sensitivity → Tasks 5 (slider), 6 (calibration). ✓
- Placeholder art (SF Symbols) → Task 4. ✓
- Edge cases: disconnect/paused force hidden → Task 3 tests; not-calibrated default → Task 2. ✓
- XcodeGen build + PostureMonitor/AppSettings unit tests → Tasks 1–3. ✓
- New `PostureBuddy/` folder, no `Co-Authored-By` trailer → all tasks. ✓

**Placeholder scan:** No TBD/TODO steps; every code step contains complete code. The Task 5 `CalibrationView` stub is explicitly created then replaced in Task 6 (each task stays buildable). ✓

**Type consistency:** `PetState { hidden, nagging }`, `PostureMonitor.ingest(quality:connectionState:at:)`, `PetOverlayWindowController.show(message:)/hide()`, `AppModel.applyThreshold/setMonitoring/startCalibration/saveCalibration/cancelCalibration`, `AppSettings.poorPostureThreshold/hasCalibrated` — names/signatures are consistent across Tasks 2–7. ✓
```
