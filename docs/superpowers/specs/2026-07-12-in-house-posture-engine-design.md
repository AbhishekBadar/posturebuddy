# In-House Posture Engine — Design

**Date:** 2026-07-12
**Status:** Approved
**Replaces:** the vendored `OldEngineCore/` Swift package

## Motivation

PostureBuddy uses roughly half of the vendored OldEngineCore package. The app never
touches the session-scoring system (start/pause/resume/end, good-posture percent),
pitch history (deliberately configured to size 1), roll/yaw, the 15 Hz UI-coalescing
timer, or any of the Codable machinery. We are replacing the package with a from-scratch,
app-shaped engine that we own outright:

- **Leaner** — ~830 lines become ~280; only what the app consumes exists.
- **Ours** — no external dependency, no license file, no attribution. The engine is
  reimplemented from PostureBuddy's behavioral requirements (documented in CLAUDE.md and
  DOCUMENTATION.md), not translated from the original source. All names, types, and the
  time-injection architecture are new.
- **More testable** — calibration and connection staleness become pure, time-injected
  state machines, deterministically testable for the first time (the original drove
  calibration off a wall-clock `Timer`).

## Architecture

Three new files in `PostureBuddy/Motion/` (app target — no Swift package, no
`Package.swift`, no second build system):

```
CMHeadphoneMotionSource (CoreMotion wrapper, pitch+timestamp callback)
  → PostureTracker (@MainActor, ObservableObject; owns timers)
       → PostureEngine (pure, time-injected; no timers/Combine/CoreMotion)
       ← @Published PostureSnapshot (published after every ingest/tick)
  → AppModel (wiring shape unchanged)
```

### PostureEngine (~150 lines)

A plain class. All state advances through explicit, date-injected entry points:

- `ingest(pitchRadians: Double, at: Date)` — validates the sample (rejects NaN,
  infinity, values outside −π…π), applies the low-pass filter, marks the connection
  fresh, and appends to calibration sampling when a sampling phase is active.
- `tick(at: Date)` — advances calibration progress and applies connection staleness
  (no-sample decay).
- `beginCalibration(at: Date)` / `cancelCalibration()` /
  `saveCalibration() -> Double?` — save returns the clamped threshold, or nil if
  calibration is not in the `done` phase.
- `noteError()` — provider failure; forces `.disconnected`.
- `var threshold: Double` — current poor-posture threshold.
- `var snapshot: PostureSnapshot` — computed current state.

Internal state: filtered pitch (EMA), last-sample time, connection phase,
calibration phase + collected samples + upright average.

### HeadphoneMotionSource (~50 lines)

```swift
protocol MotionSource {
    var isAvailable: Bool { get }
    func start(handler: @escaping (_ pitchRadians: Double, _ timestamp: Date) -> Void,
               errorHandler: @escaping (Error) -> Void)
    func stop()
}
```

`CMHeadphoneMotionSource` is the one real implementation, wrapping
`CMHeadphoneMotionManager` and delivering only pitch + timestamp. Roll and yaw are
dropped — nothing reads them. The protocol exists so engine/tracker tests never touch
CoreMotion.

### PostureTracker (~80 lines)

`@MainActor ObservableObject` — the drop-in replacement for `OldEngineTracker` in
`AppModel`. Owns:

- the `MotionSource` (injected, defaulting to `CMHeadphoneMotionSource`)
- a 2 s repeating health timer → `engine.tick(at: Date())`
- a 0.1 s repeating timer **only while calibrating** → `engine.tick(at: Date())`
  (drives the progress bar even when no samples arrive, e.g. the 3 s pause phase)

It forwards samples to `engine.ingest`, and publishes `@Published snapshot` after every
ingest and tick. **Invariant preserved:** `AppModel` receives a snapshot on every sample
tick, so `PostureMonitor`'s 5 s / 2 s hysteresis keeps advancing. No coalescing, no
deduplication at this layer — `AppModel`'s inequality-guarded `@Published` writes remain
the rate limiter for SwiftUI.

The tracker keeps running when monitoring is toggled off (unchanged invariant — motion
updates drive the menu-bar connection status; `PostureMonitor` ignores samples while
paused).

## Types

All `Equatable`, none `Codable` (nothing serializes them):

```swift
struct PostureSnapshot: Equatable {
    let pitchDegrees: Double        // filtered
    let quality: PostureQuality
    let connection: ConnectionPhase
    let calibration: CalibrationPhase
}

enum PostureQuality { case good, poor }

enum ConnectionPhase { case disconnected, connecting, connected }

enum CalibrationPhase: Equatable {
    case idle
    case samplingUpright(progress: Double)   // 5 s, records pitch
    case pause(progress: Double)             // 3 s, "get ready to slouch"
    case samplingSlouch(progress: Double)    // 5 s, records pitch
    case done(threshold: Double)
}
```

Removed relative to the original: `OldEngineSample` (roll/yaw/timestamp struct),
`OldEngineSessionSnapshot`, `OldEngineSessionSummary`, `pitchHistory`,
`goodPosturePercent`, `normalAirPodsOffset`, `OldEngineConfiguration` (the engine's
tunables become internal constants; the only externally-set value is `threshold`).

## Behavior

Identical to today unless listed under "Visible change":

- Default threshold **−22°**, valid range **−35…−5** (negative pitch = head tilted
  down; −5 is the strict end, −35 relaxed).
- Quality: `filteredPitchDegrees < threshold` → `.poor`.
- Low-pass filter: exponential moving average, factor **0.4** (same smoothing).
- Calibration: 5 s upright sampling → 3 s pause → 5 s slouch sampling; threshold =
  midpoint of the two phase averages, **clamped to −35…−5** inside the engine.
  Saving returns the clamped value; discarding leaves the old threshold intact.
- Connection freshness: first valid sample → `.connected`; ≥ 5 s without samples →
  `.connecting`; ≥ 10 s → `.disconnected`; provider error → `.disconnected`;
  `start()` before any sample → `.connecting`.

### Visible change (approved)

Connection states collapse from five to three. Timings are unchanged; only labels merge:

| Situation | Old menu text | New menu text |
|---|---|---|
| Motion silent ≥ 5 s | "Reconnecting…" | "Connecting to AirPods…" |
| Provider error | "AirPods error" | "AirPods not connected" |
| Startup / silent ≥ 10 s / receiving samples | unchanged | unchanged |

`PostureMonitor` only checks `== .connected`, so nag behavior is untouched.

## App-side changes

Mechanical; no logic changes beyond the listed cleanup:

- **AppModel** — `OldEngineTracker` → `PostureTracker`; `statusText` shrinks to three
  cases; `applyThreshold` writes `tracker.threshold`; `saveCalibration()` uses the
  returned threshold directly (removes the "write into config, read config back" dance);
  the `config.pitchHistorySize = 1` workaround is deleted (no pitch history exists).
- **PostureMonitor** — `ingest(quality:connectionState:at:)` takes
  `PostureQuality` / `ConnectionPhase`; hysteresis logic untouched.
- **CalibrationView** — switch-case renames onto `CalibrationPhase`; same four screens,
  same user-facing strings; `done(threshold:)` carries only the value the view shows.
- **AppSettings** — default-threshold fallback reads the engine's default constant.

## Repo cleanup

- Delete `OldEngineCore/` entirely (sources, tests, LICENSE, `.build`).
- `project.yml` — remove the local-package dependency; run `xcodegen generate`.
- **README** — remove the OldEngine credit line.
- **CLAUDE.md** — delete the "Vendored engine" section; update the architecture diagram,
  commands (no more `(cd OldEngineCore && swift test)`), test counts, and the invariant
  wording that references `OldEngineConfiguration`.
- **DOCUMENTATION.md** — scrub OldEngine/OldEngineCore mentions.

## Testing

New `PostureEngineTests` in `PostureBuddyTests` (~10 tests, all pure, injected dates,
no mocks of CoreMotion needed):

1. Validation: NaN / infinity / out-of-range pitch is ignored (no state change).
2. Filter: EMA smoothing converges toward input; single spike is damped.
3. Quality: classification flips on either side of the threshold.
4. Connection: `.connecting` on start → `.connected` on first sample →
   `.connecting` after 5 s of tick-only silence → `.disconnected` after 10 s;
   `noteError()` → `.disconnected`.
5. Calibration walkthrough: phases advance with ticks, progress reaches 1.0 per phase,
   threshold = midpoint of phase averages.
6. Calibration clamping at both ends (below −35, above −5).
7. Cancel mid-calibration returns to `.idle`, threshold unchanged.
8. `saveCalibration()` returns the value only from `done`, nil otherwise.

Existing tests: `PostureMonitorTests` (8) and `AppSettingsTests` (2) survive with type
renames only. `OldEngineCoreTests` (8) are deleted with the package; their coverage is
superseded by the above.

Verification: `xcodebuild test -scheme PostureBuddy -destination 'platform=macOS'`
(single target now). Calibration window, menu status, and the nag overlay still require
a manual run with real AirPods — do not claim they pass without it.
