# In-House Posture Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the vendored `AirPostureCore/` Swift package with a from-scratch, app-owned posture engine (`PostureEngine` + `CMHeadphoneMotionSource` + `PostureTracker`) in the app target, then delete the package and scrub its attribution.

**Architecture:** A pure, time-injected `PostureEngine` (low-pass filter, quality classification, connection freshness, calibration state machine — all driven by `ingest(pitchRadians:at:)` and `tick(at:)` with caller-supplied `Date`s), a thin `CMHeadphoneMotionManager` wrapper behind a `MotionSource` protocol, and a `@MainActor` `PostureTracker` that owns the wall-clock timers and publishes a `PostureSnapshot` after every ingest/tick. `AppModel` wiring shape is unchanged. Spec: `docs/superpowers/specs/2026-07-12-in-house-posture-engine-design.md`.

**Tech Stack:** Swift 5.9, SwiftUI + AppKit, CoreMotion, XCTest, XcodeGen. macOS 14.0 deployment target.

## Global Constraints

- The repo root is the project root. All commands run from the repo root.
- `PostureBuddy.xcodeproj` is generated and git-ignored — run `xcodegen generate` after **any** file add/remove/move or `project.yml` change, before building.
- Build/test with `xcodebuild`, NOT SourceKit/IDE diagnostics — the IDE shows false errors in this project ("No such module", "'main' attribute cannot be used…"). Trust `xcodebuild` output only.
- `xcodebuild` output always contains one `appintentsmetadataprocessor` `warning:` line — it is noise, not a compiler warning.
- Full test suite: `xcodebuild test -scheme PostureBuddy -destination 'platform=macOS'`. Single class: append `-only-testing:PostureBuddyTests/<ClassName>`.
- Git commits **must not include a `Co-Authored-By` trailer** (repo rule).
- Threshold semantics everywhere: negative degrees; poor posture is `pitch < threshold`; valid range `-35.0 ... -5.0`; **−5 is the strict end, −35 is relaxed**; default **−22.0**.
- Timings (must not change): low-pass filter factor **0.4**; connection stale after **5 s** of sample silence, disconnected after **10 s**; calibration phases **5 s / 3 s / 5 s**.
- User-facing wording calls the character a "pixel-art version of you", never a "pet".
- Do NOT edit anything under `AirPostureCore/` at any point; it is deleted wholesale in Task 6.
- `CLAUDE.md` is git-ignored (local only) — edit it in Task 7 but never `git add` it.

---

### Task 1: PostureEngine core — types, sample validation, filter, quality

**Files:**
- Create: `PostureBuddy/Motion/PostureEngine.swift`
- Test: `PostureBuddyTests/PostureEngineTests.swift`

**Interfaces:**
- Consumes: nothing (pure Foundation).
- Produces (later tasks rely on these exact names):
  - `enum PostureQuality { case good, poor }`
  - `enum ConnectionPhase { case disconnected, connecting, connected }`
  - `enum CalibrationPhase: Equatable { case idle, samplingUpright(progress: Double), pause(progress: Double), samplingSlouch(progress: Double), done(threshold: Double) }`
  - `struct PostureSnapshot: Equatable { let pitchDegrees: Double; let quality: PostureQuality; let connection: ConnectionPhase; let calibration: CalibrationPhase }`
  - `final class PostureEngine` with `static let defaultThreshold: Double`, `static let thresholdRange: ClosedRange<Double>`, `var threshold: Double`, `var snapshot: PostureSnapshot`, `init(threshold:)`, `func ingest(pitchRadians: Double, at date: Date)`

- [ ] **Step 1: Write the failing tests**

Create `PostureBuddyTests/PostureEngineTests.swift`:

```swift
import XCTest
@testable import PostureBuddy

final class PostureEngineTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
    private func radians(_ degrees: Double) -> Double { degrees * .pi / 180.0 }

    // MARK: Validation, filter, quality

    func testRejectsNaNInfinityAndOutOfRangeSamples() {
        let engine = PostureEngine()
        engine.ingest(pitchRadians: Double.nan, at: at(0))
        engine.ingest(pitchRadians: Double.infinity, at: at(1))
        engine.ingest(pitchRadians: 4.0, at: at(2))   // > π
        engine.ingest(pitchRadians: -4.0, at: at(3))  // < -π
        XCTAssertEqual(engine.snapshot.pitchDegrees, 0.0, accuracy: 0.0001)
        XCTAssertEqual(engine.snapshot.quality, .good)
    }

    func testFirstSampleSeedsFilterDirectly() {
        let engine = PostureEngine()
        engine.ingest(pitchRadians: radians(-10), at: at(0))
        XCTAssertEqual(engine.snapshot.pitchDegrees, -10.0, accuracy: 0.0001)
    }

    func testFilterSmoothsSubsequentSamples() {
        let engine = PostureEngine()
        engine.ingest(pitchRadians: radians(-10), at: at(0))
        engine.ingest(pitchRadians: radians(-20), at: at(1))
        // EMA factor 0.4: -10 * 0.6 + -20 * 0.4 = -14
        XCTAssertEqual(engine.snapshot.pitchDegrees, -14.0, accuracy: 0.0001)
    }

    func testQualityFlipsOnThreshold() {
        let slouched = PostureEngine()                 // default threshold -22
        slouched.ingest(pitchRadians: radians(-30), at: at(0))
        XCTAssertEqual(slouched.snapshot.quality, .poor)

        let upright = PostureEngine()
        upright.ingest(pitchRadians: radians(-10), at: at(0))
        XCTAssertEqual(upright.snapshot.quality, .good)
    }

    func testCustomThresholdIsRespected() {
        let engine = PostureEngine(threshold: -10.0)
        engine.ingest(pitchRadians: radians(-15), at: at(0))
        XCTAssertEqual(engine.snapshot.quality, .poor)
    }
}
```

- [ ] **Step 2: Regenerate the project and run tests to verify they fail**

```bash
xcodegen generate
xcodebuild test -scheme PostureBuddy -destination 'platform=macOS' -only-testing:PostureBuddyTests/PostureEngineTests
```

Expected: **BUILD FAILURE** — `cannot find 'PostureEngine' in scope` (the type doesn't exist yet; a compile error is the failing state here).

- [ ] **Step 3: Write the minimal implementation**

Create `PostureBuddy/Motion/PostureEngine.swift`:

```swift
import Foundation

// MARK: - Snapshot types

enum PostureQuality: Equatable {
    case good
    case poor
}

enum ConnectionPhase: Equatable {
    case disconnected
    case connecting
    case connected
}

enum CalibrationPhase: Equatable {
    case idle
    case samplingUpright(progress: Double)
    case pause(progress: Double)
    case samplingSlouch(progress: Double)
    case done(threshold: Double)
}

struct PostureSnapshot: Equatable {
    let pitchDegrees: Double
    let quality: PostureQuality
    let connection: ConnectionPhase
    let calibration: CalibrationPhase
}

// MARK: - PostureEngine

/// Pure, time-injected posture engine: low-pass filters AirPods head pitch,
/// classifies posture quality against a threshold, tracks connection
/// freshness, and runs the guided calibration state machine.
///
/// No timers, no Combine, no CoreMotion — every state change happens inside
/// `ingest(pitchRadians:at:)` or `tick(at:)` with caller-supplied dates, so
/// all behavior is deterministically testable.
final class PostureEngine {
    static let defaultThreshold: Double = -22.0
    /// Valid threshold bounds in degrees: -5 is the strict end, -35 relaxed.
    static let thresholdRange: ClosedRange<Double> = -35.0 ... -5.0

    private static let filterFactor: Double = 0.4

    /// Poor-posture threshold in degrees; filtered pitch below it is a slouch.
    var threshold: Double

    private var filteredPitch: Double = 0.0
    private var hasSample = false
    private var connection: ConnectionPhase = .disconnected
    private var calibration: CalibrationPhase = .idle

    init(threshold: Double = PostureEngine.defaultThreshold) {
        self.threshold = threshold
    }

    var snapshot: PostureSnapshot {
        PostureSnapshot(
            pitchDegrees: filteredPitch,
            quality: filteredPitch < threshold ? .poor : .good,
            connection: connection,
            calibration: calibration
        )
    }

    func ingest(pitchRadians: Double, at date: Date) {
        guard pitchRadians.isFinite,
              (-Double.pi ... Double.pi).contains(pitchRadians) else { return }

        let pitchDegrees = pitchRadians * 180.0 / .pi
        filteredPitch = hasSample
            ? filteredPitch * (1.0 - Self.filterFactor) + pitchDegrees * Self.filterFactor
            : pitchDegrees
        hasSample = true
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme PostureBuddy -destination 'platform=macOS' -only-testing:PostureBuddyTests/PostureEngineTests
```

Expected: **TEST SUCCEEDED**, 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add PostureBuddy/Motion/PostureEngine.swift PostureBuddyTests/PostureEngineTests.swift
git commit -m "feat: add PostureEngine core with sample validation, low-pass filter, quality classification"
```

---

### Task 2: PostureEngine connection lifecycle

**Files:**
- Modify: `PostureBuddy/Motion/PostureEngine.swift`
- Test: `PostureBuddyTests/PostureEngineTests.swift` (append)

**Interfaces:**
- Consumes: Task 1's `PostureEngine`.
- Produces: `func start(at date: Date)`, `func tick(at date: Date)`, `func noteError()`. Connection semantics: `.disconnected` until `start`; `start` → `.connecting` (unless already `.connected`); any valid sample → `.connected`; ≥ 5 s sample silence at `tick` → `.connecting`; ≥ 10 s → `.disconnected`; `noteError()` → `.disconnected`. Invalid samples must NOT refresh freshness.

- [ ] **Step 1: Append the failing tests**

Append inside `PostureEngineTests` (before the closing brace):

```swift
    // MARK: Connection lifecycle

    func testStartMovesDisconnectedToConnecting() {
        let engine = PostureEngine()
        XCTAssertEqual(engine.snapshot.connection, .disconnected)
        engine.start(at: at(0))
        XCTAssertEqual(engine.snapshot.connection, .connecting)
    }

    func testFirstSampleConnects() {
        let engine = PostureEngine()
        engine.start(at: at(0))
        engine.ingest(pitchRadians: radians(-10), at: at(1))
        XCTAssertEqual(engine.snapshot.connection, .connected)
    }

    func testSampleSilenceDegradesConnectionThenSampleRecovers() {
        let engine = PostureEngine()
        engine.start(at: at(0))
        engine.ingest(pitchRadians: radians(-10), at: at(1))

        engine.tick(at: at(3))     // 2 s silence: still connected
        XCTAssertEqual(engine.snapshot.connection, .connected)

        engine.tick(at: at(6.5))   // 5.5 s silence: stale
        XCTAssertEqual(engine.snapshot.connection, .connecting)

        engine.tick(at: at(11.5))  // 10.5 s silence: gone
        XCTAssertEqual(engine.snapshot.connection, .disconnected)

        engine.ingest(pitchRadians: radians(-10), at: at(12))
        XCTAssertEqual(engine.snapshot.connection, .connected)
    }

    func testTickBeforeStartKeepsDisconnected() {
        let engine = PostureEngine()
        engine.tick(at: at(60))
        XCTAssertEqual(engine.snapshot.connection, .disconnected)
    }

    func testInvalidSampleDoesNotRefreshConnection() {
        let engine = PostureEngine()
        engine.start(at: at(0))
        engine.ingest(pitchRadians: radians(-10), at: at(1))
        engine.ingest(pitchRadians: Double.nan, at: at(8))  // must not count
        engine.tick(at: at(8))                              // 7 s since last valid
        XCTAssertEqual(engine.snapshot.connection, .connecting)
    }

    func testErrorForcesDisconnected() {
        let engine = PostureEngine()
        engine.start(at: at(0))
        engine.ingest(pitchRadians: radians(-10), at: at(1))
        engine.noteError()
        XCTAssertEqual(engine.snapshot.connection, .disconnected)
    }
```

- [ ] **Step 2: Run tests to verify the new ones fail**

```bash
xcodebuild test -scheme PostureBuddy -destination 'platform=macOS' -only-testing:PostureBuddyTests/PostureEngineTests
```

Expected: **BUILD FAILURE** — `value of type 'PostureEngine' has no member 'start'` (and `tick`, `noteError`).

- [ ] **Step 3: Implement connection tracking**

In `PostureBuddy/Motion/PostureEngine.swift`:

Add two constants below `filterFactor`:

```swift
    private static let staleInterval: TimeInterval = 5.0
    private static let disconnectInterval: TimeInterval = 10.0
```

Add two stored properties below `hasSample`:

```swift
    private var isStarted = false
    private var lastSampleAt: Date = .distantPast
```

Add three methods after `snapshot`:

```swift
    /// Motion updates are starting; connection is pending until a sample arrives.
    func start(at date: Date) {
        isStarted = true
        lastSampleAt = date
        if connection != .connected {
            connection = .connecting
        }
    }

    /// Advances time-based state: connection staleness (and, later, calibration).
    func tick(at date: Date) {
        guard isStarted else { return }
        let silence = date.timeIntervalSince(lastSampleAt)
        if silence >= Self.disconnectInterval {
            connection = .disconnected
        } else if silence >= Self.staleInterval {
            connection = .connecting
        }
    }

    /// The motion provider reported a failure.
    func noteError() {
        connection = .disconnected
    }
```

And extend `ingest` — after the `hasSample = true` line, add:

```swift
        lastSampleAt = date
        connection = .connected
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme PostureBuddy -destination 'platform=macOS' -only-testing:PostureBuddyTests/PostureEngineTests
```

Expected: **TEST SUCCEEDED**, 11 tests pass.

- [ ] **Step 5: Commit**

```bash
git add PostureBuddy/Motion/PostureEngine.swift PostureBuddyTests/PostureEngineTests.swift
git commit -m "feat: track connection freshness in PostureEngine"
```

---

### Task 3: PostureEngine calibration state machine

**Files:**
- Modify: `PostureBuddy/Motion/PostureEngine.swift`
- Test: `PostureBuddyTests/PostureEngineTests.swift` (append)

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces: `func beginCalibration(at date: Date)`, `func cancelCalibration()`, `func saveCalibration() -> Double?`. Phase flow driven by `tick`: `samplingUpright` (5 s, records raw pitch) → `pause` (3 s) → `samplingSlouch` (5 s, records raw pitch) → `done(threshold:)` where threshold = midpoint of the two phase averages clamped to `thresholdRange`. `saveCalibration()` applies the value to `threshold`, returns it, and resets to `.idle`; returns nil unless in `.done`. Note: calibration records the **raw** (unfiltered) sample in degrees — averaging over 5 s makes filtering redundant, and raw samples keep the math exact.

- [ ] **Step 1: Append the failing tests**

Append inside `PostureEngineTests`:

```swift
    // MARK: Calibration

    /// Runs begin → upright samples → pause → slouch samples → done.
    /// uprightDegrees/slouchDegrees are the constant pitch fed in each phase.
    private func calibrate(_ engine: PostureEngine,
                           uprightDegrees: Double,
                           slouchDegrees: Double) {
        engine.beginCalibration(at: at(0))
        engine.ingest(pitchRadians: radians(uprightDegrees), at: at(1))
        engine.ingest(pitchRadians: radians(uprightDegrees), at: at(2))
        engine.tick(at: at(5))     // upright done → pause
        engine.tick(at: at(8))     // pause done → samplingSlouch
        engine.ingest(pitchRadians: radians(slouchDegrees), at: at(9))
        engine.ingest(pitchRadians: radians(slouchDegrees), at: at(10))
        engine.tick(at: at(13))    // slouch done → done(threshold:)
    }

    func testCalibrationWalkthroughPhasesAndProgress() {
        let engine = PostureEngine()
        engine.start(at: at(0))
        engine.beginCalibration(at: at(0))
        XCTAssertEqual(engine.snapshot.calibration, .samplingUpright(progress: 0.0))

        engine.tick(at: at(2.5))
        XCTAssertEqual(engine.snapshot.calibration, .samplingUpright(progress: 0.5))

        engine.ingest(pitchRadians: radians(-5), at: at(3))
        engine.tick(at: at(5))
        XCTAssertEqual(engine.snapshot.calibration, .pause(progress: 0.0))

        engine.tick(at: at(6.5))
        XCTAssertEqual(engine.snapshot.calibration, .pause(progress: 0.5))

        engine.tick(at: at(8))
        XCTAssertEqual(engine.snapshot.calibration, .samplingSlouch(progress: 0.0))

        engine.ingest(pitchRadians: radians(-25), at: at(9))
        engine.tick(at: at(13))
        // Midpoint of -5 and -25 = -15.
        XCTAssertEqual(engine.snapshot.calibration, .done(threshold: -15.0))
    }

    func testCalibrationClampsToStrictBound() {
        let engine = PostureEngine()
        engine.start(at: at(0))
        calibrate(engine, uprightDegrees: 20, slouchDegrees: 10)  // midpoint +15
        XCTAssertEqual(engine.snapshot.calibration, .done(threshold: -5.0))
    }

    func testCalibrationClampsToRelaxedBound() {
        let engine = PostureEngine()
        engine.start(at: at(0))
        calibrate(engine, uprightDegrees: -45, slouchDegrees: -65)  // midpoint -55
        XCTAssertEqual(engine.snapshot.calibration, .done(threshold: -35.0))
    }

    func testCancelCalibrationReturnsToIdleWithoutChangingThreshold() {
        let engine = PostureEngine()
        engine.start(at: at(0))
        engine.beginCalibration(at: at(0))
        engine.tick(at: at(2))
        engine.cancelCalibration()
        XCTAssertEqual(engine.snapshot.calibration, .idle)
        XCTAssertEqual(engine.threshold, PostureEngine.defaultThreshold, accuracy: 0.0001)
    }

    func testSaveCalibrationAppliesAndReturnsThreshold() {
        let engine = PostureEngine()
        engine.start(at: at(0))
        XCTAssertNil(engine.saveCalibration())  // nothing to save yet

        calibrate(engine, uprightDegrees: -5, slouchDegrees: -25)
        XCTAssertEqual(engine.saveCalibration() ?? .nan, -15.0, accuracy: 0.0001)
        XCTAssertEqual(engine.threshold, -15.0, accuracy: 0.0001)
        XCTAssertEqual(engine.snapshot.calibration, .idle)
    }
```

- [ ] **Step 2: Run tests to verify the new ones fail**

```bash
xcodebuild test -scheme PostureBuddy -destination 'platform=macOS' -only-testing:PostureBuddyTests/PostureEngineTests
```

Expected: **BUILD FAILURE** — `has no member 'beginCalibration'` (and `cancelCalibration`, `saveCalibration`).

- [ ] **Step 3: Implement the calibration state machine**

In `PostureBuddy/Motion/PostureEngine.swift`:

Add two constants below `disconnectInterval`:

```swift
    private static let samplingDuration: TimeInterval = 5.0
    private static let pauseDuration: TimeInterval = 3.0
```

Add three stored properties below `calibration`:

```swift
    private var phaseStartedAt: Date?
    private var phaseSamples: [Double] = []
    private var uprightAverage: Double = 0.0
```

In `ingest`, replace the two lines added in Task 2 (`lastSampleAt = date` / `connection = .connected`) with:

```swift
        lastSampleAt = date
        connection = .connected

        switch calibration {
        case .samplingUpright, .samplingSlouch:
            phaseSamples.append(pitchDegrees)
        default:
            break
        }
```

In `tick`, add a final line so the body reads:

```swift
    func tick(at date: Date) {
        guard isStarted else { return }
        let silence = date.timeIntervalSince(lastSampleAt)
        if silence >= Self.disconnectInterval {
            connection = .disconnected
        } else if silence >= Self.staleInterval {
            connection = .connecting
        }
        advanceCalibration(at: date)
    }
```

Add after `noteError()`:

```swift
    // MARK: Calibration

    func beginCalibration(at date: Date) {
        phaseSamples.removeAll()
        uprightAverage = 0.0
        calibration = .samplingUpright(progress: 0.0)
        phaseStartedAt = date
    }

    func cancelCalibration() {
        calibration = .idle
        phaseStartedAt = nil
        phaseSamples.removeAll()
    }

    /// Applies and returns the calibrated threshold, or nil if calibration
    /// hasn't reached `.done`.
    func saveCalibration() -> Double? {
        guard case .done(let value) = calibration else { return nil }
        threshold = value
        calibration = .idle
        return value
    }

    private func advanceCalibration(at date: Date) {
        guard let phaseStart = phaseStartedAt else { return }
        let elapsed = date.timeIntervalSince(phaseStart)

        switch calibration {
        case .samplingUpright:
            if elapsed >= Self.samplingDuration {
                uprightAverage = average(of: phaseSamples)
                phaseSamples.removeAll()
                calibration = .pause(progress: 0.0)
                phaseStartedAt = date
            } else {
                calibration = .samplingUpright(progress: elapsed / Self.samplingDuration)
            }
        case .pause:
            if elapsed >= Self.pauseDuration {
                calibration = .samplingSlouch(progress: 0.0)
                phaseStartedAt = date
            } else {
                calibration = .pause(progress: elapsed / Self.pauseDuration)
            }
        case .samplingSlouch:
            if elapsed >= Self.samplingDuration {
                let midpoint = (uprightAverage + average(of: phaseSamples)) / 2.0
                let clamped = min(max(midpoint, Self.thresholdRange.lowerBound),
                                  Self.thresholdRange.upperBound)
                calibration = .done(threshold: clamped)
                phaseStartedAt = nil
                phaseSamples.removeAll()
            } else {
                calibration = .samplingSlouch(progress: elapsed / Self.samplingDuration)
            }
        case .idle, .done:
            phaseStartedAt = nil
        }
    }

    private func average(of values: [Double]) -> Double {
        values.isEmpty ? 0.0 : values.reduce(0, +) / Double(values.count)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme PostureBuddy -destination 'platform=macOS' -only-testing:PostureBuddyTests/PostureEngineTests
```

Expected: **TEST SUCCEEDED**, 16 tests pass.

- [ ] **Step 5: Commit**

```bash
git add PostureBuddy/Motion/PostureEngine.swift PostureBuddyTests/PostureEngineTests.swift
git commit -m "feat: add guided calibration state machine to PostureEngine"
```

---

### Task 4: MotionSource, CMHeadphoneMotionSource, and PostureTracker

**Files:**
- Create: `PostureBuddy/Motion/HeadphoneMotionSource.swift`
- Create: `PostureBuddy/Motion/PostureTracker.swift`
- Test: `PostureBuddyTests/PostureTrackerTests.swift`

**Interfaces:**
- Consumes: Task 1–3's `PostureEngine` and snapshot types.
- Produces (Task 5's `AppModel` relies on these exact names):
  - `protocol MotionSource: AnyObject { var isAvailable: Bool { get }; func start(handler:errorHandler:); func stop() }`
  - `final class CMHeadphoneMotionSource: MotionSource`
  - `@MainActor final class PostureTracker: ObservableObject` with `@Published private(set) var snapshot: PostureSnapshot`, `var threshold: Double` (get/set), `init(threshold:source:)`, `func start()`, `func beginCalibration()`, `func cancelCalibration()`, `func saveCalibration() -> Double?`, and internal `func receive(pitchRadians: Double, at date: Date)` (the sample entry point, callable directly from tests).

- [ ] **Step 1: Write the failing tests**

Create `PostureBuddyTests/PostureTrackerTests.swift`:

```swift
import XCTest
import Combine
@testable import PostureBuddy

@MainActor
final class PostureTrackerTests: XCTestCase {
    private final class FakeMotionSource: MotionSource {
        var isAvailable = true
        private(set) var startCount = 0
        func start(handler: @escaping (Double, Date) -> Void,
                   errorHandler: @escaping (Error) -> Void) {
            startCount += 1
        }
        func stop() {}
    }

    private func radians(_ degrees: Double) -> Double { degrees * .pi / 180.0 }

    func testStartIsIdempotentAndBeginsConnecting() {
        let source = FakeMotionSource()
        let tracker = PostureTracker(source: source)
        XCTAssertEqual(tracker.snapshot.connection, .disconnected)

        tracker.start()
        tracker.start()
        XCTAssertEqual(source.startCount, 1)
        XCTAssertEqual(tracker.snapshot.connection, .connecting)
    }

    func testReceiveConnectsAndClassifies() {
        let tracker = PostureTracker(source: FakeMotionSource())
        tracker.start()
        tracker.receive(pitchRadians: radians(-30), at: Date())
        XCTAssertEqual(tracker.snapshot.connection, .connected)
        XCTAssertEqual(tracker.snapshot.quality, .poor)  // -30 < default -22
    }

    func testEverySamplePublishesEvenWhenUnchanged() {
        // PostureMonitor's hysteresis timers advance per published tick, so the
        // tracker must never coalesce or deduplicate snapshots.
        let tracker = PostureTracker(source: FakeMotionSource())
        tracker.start()
        var publishCount = 0
        let cancellable = tracker.$snapshot.dropFirst().sink { _ in publishCount += 1 }
        defer { cancellable.cancel() }

        tracker.receive(pitchRadians: radians(-10), at: Date())
        tracker.receive(pitchRadians: radians(-10), at: Date())
        XCTAssertEqual(publishCount, 2)
    }

    func testThresholdWriteReclassifiesImmediately() {
        let tracker = PostureTracker(source: FakeMotionSource())
        tracker.start()
        tracker.receive(pitchRadians: radians(-15), at: Date())
        XCTAssertEqual(tracker.snapshot.quality, .good)   // -15 > -22

        tracker.threshold = -10.0
        XCTAssertEqual(tracker.snapshot.quality, .poor)   // -15 < -10
    }
}
```

- [ ] **Step 2: Regenerate and run to verify they fail**

```bash
xcodegen generate
xcodebuild test -scheme PostureBuddy -destination 'platform=macOS' -only-testing:PostureBuddyTests/PostureTrackerTests
```

Expected: **BUILD FAILURE** — `cannot find type 'MotionSource' in scope` / `cannot find 'PostureTracker' in scope`.

- [ ] **Step 3: Write the implementation**

Create `PostureBuddy/Motion/HeadphoneMotionSource.swift`:

```swift
import CoreMotion
import Foundation

/// Abstracts AirPods head-motion delivery so the tracker is testable without
/// CoreMotion. Handlers may be called on any queue.
protocol MotionSource: AnyObject {
    var isAvailable: Bool { get }
    func start(handler: @escaping (_ pitchRadians: Double, _ timestamp: Date) -> Void,
               errorHandler: @escaping (Error) -> Void)
    func stop()
}

/// The real source: wraps CMHeadphoneMotionManager and forwards pitch only.
final class CMHeadphoneMotionSource: MotionSource {
    private let manager = CMHeadphoneMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.posturebuddy.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start(handler: @escaping (Double, Date) -> Void,
               errorHandler: @escaping (Error) -> Void) {
        guard !manager.isDeviceMotionActive else { return }
        manager.startDeviceMotionUpdates(to: queue) { motion, error in
            if let error {
                errorHandler(error)
            } else if let motion {
                handler(motion.attitude.pitch, Date())
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
```

Create `PostureBuddy/Motion/PostureTracker.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme PostureBuddy -destination 'platform=macOS' -only-testing:PostureBuddyTests/PostureTrackerTests
```

Expected: **TEST SUCCEEDED**, 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add PostureBuddy/Motion/HeadphoneMotionSource.swift PostureBuddy/Motion/PostureTracker.swift PostureBuddyTests/PostureTrackerTests.swift
git commit -m "feat: add MotionSource wrapper and PostureTracker glue"
```

---

### Task 5: Rewire the app onto the new engine

**Files:**
- Modify: `PostureBuddy/AppModel.swift` (full rewrite below)
- Modify: `PostureBuddy/PostureMonitor.swift` (full rewrite below)
- Modify: `PostureBuddy/CalibrationView.swift` (full rewrite below)
- Modify: `PostureBuddy/AppSettings.swift` (two lines)
- Modify: `PostureBuddyTests/PostureMonitorTests.swift` (imports + type names)
- Modify: `PostureBuddyTests/AppSettingsTests.swift` (imports + one constant)

**Interfaces:**
- Consumes: `PostureTracker` (Task 4), `PostureEngine.defaultThreshold` / `PostureEngine.thresholdRange` (Task 1), `PostureQuality` / `ConnectionPhase` / `CalibrationPhase` (Task 1).
- Produces: `PostureMonitor.ingest(quality: PostureQuality, connectionState: ConnectionPhase, at: Date)` — same behavior, new types. After this task the app no longer references `AirPostureCore` anywhere; the package is still linked but unused.

- [ ] **Step 1: Update the two test files first (red)**

In `PostureBuddyTests/PostureMonitorTests.swift`: delete the line `import AirPostureCore`, and change the `feed` helper's parameter types:

```swift
    private func feed(_ monitor: PostureMonitor,
                      _ quality: PostureQuality,
                      at seconds: TimeInterval,
                      connection: ConnectionPhase = .connected) {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        monitor.ingest(quality: quality,
                       connectionState: connection,
                       at: base.addingTimeInterval(seconds))
    }
```

(All test bodies are unchanged — `.poor`, `.good`, and `.disconnected` literals resolve against the new types.)

In `PostureBuddyTests/AppSettingsTests.swift`: delete the line `import AirPostureCore`, and in `testThresholdDefaultsToCoreDefaultWhenUnset` replace `AirPostureConfiguration.default.poorPostureThreshold` with `PostureEngine.defaultThreshold`.

- [ ] **Step 2: Run the suite to verify it fails**

```bash
xcodebuild test -scheme PostureBuddy -destination 'platform=macOS'
```

Expected: **BUILD FAILURE** — `PostureMonitor.ingest` still takes `AirPostureQuality`, so the updated tests don't type-check.

- [ ] **Step 3: Rewrite the four app files**

Replace `PostureBuddy/PostureMonitor.swift` with:

```swift
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
```

Replace `PostureBuddy/AppModel.swift` with:

```swift
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
```

Replace `PostureBuddy/CalibrationView.swift` with:

```swift
import SwiftUI

/// Guided calibration: records good posture, then bad posture, then lets the
/// user save the computed threshold. State comes from AppModel.calibrationState,
/// which mirrors the tracker's CalibrationPhase.
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
        case .samplingUpright:
            Text("Sit up straight and hold still…")
                .font(.headline)
        case .pause:
            Text("Great! Now get ready to slouch…")
                .font(.headline)
        case .samplingSlouch:
            Text("Now slouch the way you normally do…")
                .font(.headline)
        case .done(let threshold):
            Text("Done! Your personalized threshold is \(Int(threshold))°.")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var progressView: some View {
        switch model.calibrationState {
        case .samplingUpright(let p), .pause(let p), .samplingSlouch(let p):
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
        case .samplingUpright, .pause, .samplingSlouch:
            Button("Cancel") {
                model.cancelCalibration()
                dismiss()
            }
        case .done:
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

In `PostureBuddy/AppSettings.swift`: delete the line `import AirPostureCore`, and in `poorPostureThreshold`'s getter replace `AirPostureConfiguration.default.poorPostureThreshold` with `PostureEngine.defaultThreshold`.

- [ ] **Step 4: Run the full suite to verify it passes**

```bash
xcodebuild test -scheme PostureBuddy -destination 'platform=macOS'
```

Expected: **TEST SUCCEEDED** — all classes pass (PostureEngineTests 16, PostureTrackerTests 4, PostureMonitorTests 8, AppSettingsTests 4, NagMessagesTests). Also confirm no app source still references the old module:

```bash
grep -rn "AirPosture" PostureBuddy/ PostureBuddyTests/ --include="*.swift"
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add PostureBuddy/AppModel.swift PostureBuddy/PostureMonitor.swift PostureBuddy/CalibrationView.swift PostureBuddy/AppSettings.swift PostureBuddyTests/PostureMonitorTests.swift PostureBuddyTests/AppSettingsTests.swift
git commit -m "refactor: rewire app onto in-house PostureTracker"
```

---

### Task 6: Remove the AirPostureCore package

**Files:**
- Modify: `project.yml`
- Delete: `AirPostureCore/` (entire directory, including LICENSE and `.build`)

**Interfaces:**
- Consumes: Task 5 (no source references remain).
- Produces: a project with a single build system and no external packages.

- [ ] **Step 1: Edit `project.yml`**

Remove the whole `packages:` block:

```yaml
packages:
  AirPostureCore:
    path: AirPostureCore
```

Remove `- package: AirPostureCore` from the `PostureBuddy` target's `dependencies:` (leaving the key absent — it has no other entries), and remove the same line from `PostureBuddyTests`' `dependencies:` (leaving `- target: PostureBuddy`).

- [ ] **Step 2: Delete the package**

```bash
git rm -r AirPostureCore
rm -rf AirPostureCore   # clears the untracked .build directory git rm leaves behind
```

- [ ] **Step 3: Regenerate and run the full suite**

```bash
xcodegen generate
xcodebuild test -scheme PostureBuddy -destination 'platform=macOS'
```

Expected: **TEST SUCCEEDED**. If Xcode (not xcodebuild) later complains "Missing package product 'AirPostureCore'", that's the stale-DerivedData gotcha: `rm -rf ~/Library/Developer/Xcode/DerivedData/PostureBuddy-*` and regenerate.

- [ ] **Step 4: Commit**

```bash
git add project.yml
git commit -m "chore: remove vendored AirPostureCore package"
```

(`git rm` already staged the deletions.)

---

### Task 7: Documentation scrub

**Files:**
- Modify: `README.md`
- Modify: `DOCUMENTATION.md`
- Modify: `CLAUDE.md` (**git-ignored — edit but do NOT commit**)

**Interfaces:**
- Consumes: the final code shape from Tasks 1–6.
- Produces: docs with no AirPosture/AirPostureCore/Allen Lee mentions.

- [ ] **Step 1: README.md**

1. Replace the first paragraph of "How it works" (the sentence spanning "PostureBuddy uses the **AirPostureCore** engine … head-tilt via `CMHeadphoneMotionManager`.") so the section starts:

   > PostureBuddy reads AirPods head-tilt via `CMHeadphoneMotionManager` through its own small posture engine (`PostureBuddy/Motion/`). When your head stays tilted past your calibrated threshold for ~5 seconds, …

   (rest of the sentence and the quote block unchanged).
2. In "Test", replace both lines of the code block with the single line:

   ```bash
   xcodebuild test -scheme PostureBuddy -destination 'platform=macOS'
   ```

   and drop the `# 15 app tests` comment (counts drift; say nothing).
3. In "Notes", replace the `AirPostureCore` bullet ("- `AirPostureCore` is vendored locally … no external project dependencies.") with:

   > - The posture engine (`PostureBuddy/Motion/` — filter, classification, connection tracking, calibration) is part of the app target; this project has no external dependencies.
4. Delete the entire "## Credits" section.

- [ ] **Step 2: DOCUMENTATION.md**

1. **Architecture diagram (§2):** replace the top two boxes and their annotations:
   - `┌ CMHeadphoneMotionProvider ┐  wraps CMHeadphoneMotionManager` box annotation "vendored Swift package (AirPostureCore/)" → "app target (PostureBuddy/Motion/)"
   - `CMHeadphoneMotionProvider` → `CMHeadphoneMotionSource`
   - `AirPostureTracker` → `PostureTracker` + `PostureEngine` (keep the same responsibility caption: "validates samples, low-pass filters pitch, classifies good/poor vs threshold, tracks connection health, runs calibration")
   - `@Published AirPostureSnapshot (quality, connectionState, …)` → `@Published PostureSnapshot (quality, connection, …)`
2. **Components table (§2):** replace the `AirPostureCore` row with two rows:

   | `PostureEngine` | `PostureBuddy/Motion/PostureEngine.swift` | Pure, time-injected posture engine: sample validation, low-pass pitch filter (factor 0.4), good/poor classification (`pitch < threshold` → poor), connection freshness, guided calibration. Fully unit-tested with injected dates. |
   | `PostureTracker` / `CMHeadphoneMotionSource` | `PostureBuddy/Motion/` | `@MainActor` glue: wraps `CMHeadphoneMotionManager`, forwards samples to the engine, owns the 2 s health tick and the 0.1 s calibration-progress tick, publishes `PostureSnapshot` on every sample. |

3. **Data flow (§2):** `AirPostureSnapshot` → `PostureSnapshot`; the closing sentence "…write the same value: `tracker.configuration.poorPostureThreshold` + `AppSettings`" → "…write the same value: `tracker.threshold` + `AppSettings` (persisted)."
4. **Timings table (§3):** `Poor-posture rule` row's Where column `core updateSnapshot()` → `PostureEngine.snapshot`; `Default threshold` row's Where column `AirPostureConfiguration.default` → `PostureEngine.defaultThreshold`; `Threshold bounds` Where column → `PostureEngine.thresholdRange`.
5. **Tests section (§4-ish, "Tests (15 app tests + 8 vendored-core tests)"):** heading text → "Tests:"; delete the `(cd AirPostureCore && swift test)` line; delete the "Missing package product 'AirPostureCore'" troubleshooting bullet entirely.
6. **Testing strategy:** add `PostureEngine` (16 tests — validation, filter, quality, connection lifecycle, calibration walkthrough/clamping) and `PostureTracker` (4 tests — idempotent start, publish-per-sample invariant) to the unit-tested list; delete the sentence "The core package has its own 8 tests using `MockHeadphoneMotionProvider`."
7. **Project layout (§5):** delete the four `AirPostureCore/` tree lines; under `PostureBuddy/` add a line `│   ├── Motion/                      PostureEngine, PostureTracker, CMHeadphoneMotionSource`; in the `PostureBuddyTests/` line append `PostureEngineTests, PostureTrackerTests`.
8. **§8 Licensing & credits:** replace the whole "Licensing & credits" bullet with:

   > - **Dependencies:** none — the posture engine is part of the app; no third-party code.
9. Sanity check:

   ```bash
   grep -rn "AirPosture\|Allen" README.md DOCUMENTATION.md
   ```

   Expected: no output.

- [ ] **Step 3: CLAUDE.md (local only — do not commit)**

1. "What this is": no change needed (doesn't name the engine).
2. **Commands:** delete the `(cd AirPostureCore && swift test)` line; update the test count comment to match reality after Task 6 (run the suite and use the reported number).
3. **Architecture:** update the pipeline diagram to `CMHeadphoneMotionSource → PostureTracker/PostureEngine → @Published PostureSnapshot → AppModel → PostureMonitor → PetOverlayWindowController`; replace the `AirPostureCore/` bullet with a bullet describing `PostureBuddy/Motion/` (pure time-injected engine + tracker glue, fully unit-tested).
4. **Invariants:** the `@Published`/ingest/receive(on:) invariants stay; delete the `config.pitchHistorySize = 1` invariant (no pitch history exists); reword the calibration-clamp invariant: the engine clamps, and `saveCalibration()` still routes through `applyThreshold()` for consistent persistence.
5. **Delete the whole "Vendored engine (`AirPostureCore/`)" section.**
6. **Testing:** replace the bullet list with: `PostureEngineTests` (16), `PostureTrackerTests` (4), `PostureMonitorTests` (8), `AppSettingsTests` (4), `NagMessagesTests`; keep the "Not covered / do not claim GUI passes" wording.
7. **Gotchas:** delete the "Missing package product 'AirPostureCore'" bullet and the `AirPostureCore/.build` sibling-directory note.

- [ ] **Step 4: Commit (tracked docs only)**

```bash
git add README.md DOCUMENTATION.md
git commit -m "docs: describe the in-house posture engine, drop AirPostureCore references"
```

Verify CLAUDE.md was not staged: `git status --short` must not list it.

---

## Final verification (after Task 7)

```bash
xcodegen generate
xcodebuild -scheme PostureBuddy -destination 'platform=macOS' build 2>&1 | grep "warning:" | grep -v appintents   # expect: empty
xcodebuild test -scheme PostureBuddy -destination 'platform=macOS'                                                # expect: TEST SUCCEEDED
grep -rn "AirPosture" --include="*.swift" --include="*.yml" --include="*.md" . | grep -v docs/superpowers | grep -v CLAUDE.md   # expect: empty
```

Manual verification (needs real AirPods + GUI — **do not claim these pass; ask the user**): menu status transitions, calibration walkthrough (progress bars, Save/Discard), nag appears after 5 s slouch and dismisses after 2 s recovery, sensitivity slider still labeled Relaxed↔Strict with live status updates during drag.
