# PostureBuddy — Project Documentation

A native macOS **menu-bar app** that watches your sitting posture through your
**AirPods** and, when you slouch, sends an animated pixel character walking onto
your screen to tell you to **"Sit straight!"** — then walks away (fades out) once
you've corrected yourself.

No camera, no network, no analytics. Everything runs locally.

---

## 1. How it works (user's view)

1. **Launch** — PostureBuddy appears only in the menu bar (no Dock icon). On the
   very first run it opens a guided calibration window.
2. **Calibration** — you sit up straight for ~5 s, then slouch for ~5 s. The app
   computes a personalized head-tilt threshold from the two averages and saves it.
3. **Monitoring** — with AirPods in, the app continuously reads your head pitch.
   - Slouch past your threshold and *stay* slouched for **5 seconds** → the pet
     GIF appears bottom-right: it **walks in from the right edge, stops, stands**,
     and a **"Sit straight!" speech bubble** pops up ~1 s before the walk animation
     ends. The character then stays frozen, staring at you.
   - Sit up straight and *hold it* for **2 seconds** → the pet fades out.
4. **Menu bar** — click the icon for: connection status, a **Monitor my posture**
   toggle, a **Sensitivity** slider (Relaxed ↔ Strict), **Recalibrate…**, and Quit.

The overlay never steals keyboard/mouse focus and is **click-through** — it cannot
interrupt whatever you're doing.

### Hardware / OS requirements

- **macOS 14+** (Sonoma or later)
- **AirPods with head tracking**: AirPods Pro (any gen), AirPods 3rd gen+,
  AirPods Max, or compatible Beats. (Head-tracking data via `CMHeadphoneMotionManager`.)
- To build: Xcode 16+ and XcodeGen (`brew install xcodegen`).

---

## 2. Architecture

```
   AirPods motion (~25 Hz)
          │
          ▼
┌─────────────────────────┐   vendored Swift package (AirPostureCore/)
│  CMHeadphoneMotionProvider │  wraps CMHeadphoneMotionManager
└──────────┬──────────────┘
           ▼
┌─────────────────────────┐
│    AirPostureTracker    │  validates samples, low-pass filters pitch,
│    (@MainActor, Combine)│  classifies good/poor vs threshold, tracks
└──────────┬──────────────┘  connection health, runs calibration
           │  @Published AirPostureSnapshot (quality, connectionState, …)
           ▼
┌─────────────────────────┐   app target (PostureBuddy/PostureBuddy/)
│        AppModel         │  central coordinator; owns everything below
└───┬───────────┬─────────┘
    │           │
    ▼           ▼
┌─────────┐ ┌──────────────────────────┐
│Posture- │ │ MenuBarContentView /      │
│Monitor  │ │ CalibrationView (SwiftUI) │
└───┬─────┘ └──────────────────────────┘
    │  PetState (.hidden / .nagging)
    ▼
┌──────────────────────────┐
│ PetOverlayWindowController│  borderless, non-activating, click-through
│   ├─ GIFPlayerView        │  NSPanel bottom-right; plays GIF once & holds
│   └─ SpeechBubbleView     │  "Sit straight!" bubble, timed to the GIF
└──────────────────────────┘
```

### Components

| Unit | File | Responsibility |
|---|---|---|
| `AirPostureCore` | `AirPostureCore/` (SPM package) | AirPods motion + posture engine: sample validation, low-pass pitch filter (factor 0.4), good/poor classification (`adjustedPitch < threshold` → poor), connection state machine, guided calibration, session scoring. **Vendored; self-contained; MIT-licensed (see `AirPostureCore/LICENSE`).** |
| `AppModel` | `PostureBuddy/AppModel.swift` | Central coordinator. Applies the persisted threshold, subscribes to tracker snapshots, feeds `PostureMonitor`, drives the overlay from `PetState`, exposes menu state, and orchestrates calibration (pause nags → run → clamp + save result). |
| `PostureMonitor` | `PostureBuddy/PostureMonitor.swift` | The nag decision. Pure, injectable-time hysteresis: `.poor` sustained ≥ **5 s** → `.nagging`; then `.good` sustained ≥ **2 s** → `.hidden`. Any disconnect or pause instantly hides and resets. Fully unit-tested. |
| `PetState` | `PostureBuddy/PetState.swift` | Two-case enum: `.hidden` / `.nagging`. |
| `AppSettings` | `PostureBuddy/AppSettings.swift` | `UserDefaults` persistence for `poorPostureThreshold` (defaults to −22°) and `hasCalibrated`. Unit-tested. |
| `PetOverlayWindowController` | `PostureBuddy/PetOverlayWindowController.swift` | The on-screen pet. Borderless, transparent, **non-activating**, **click-through** `NSPanel` (floating level, joins all Spaces, works over full-screen apps). Positions bottom-right with the character entering from the screen edge. Fades in/out; schedules the speech bubble. |
| `GIFPlayerView` | `PostureBuddy/GIFPlayerView.swift` | Custom `NSImageView` that plays the GIF **exactly once and freezes on the last frame** (no looping). Decodes frames on demand with `shouldCache: false` (~one frame in memory). Exposes `totalDuration` from real frame delays. |
| `SpeechBubbleView` | `PostureBuddy/SpeechBubbleView.swift` | SwiftUI white rounded bubble + tail with the "Sit straight!" text (the GIF art has no text of its own). |
| `MenuBarContentView` | `PostureBuddy/MenuBarContentView.swift` | Menu-bar popover UI: status, monitor toggle, sensitivity slider (−35…−5°), Recalibrate…, Quit. |
| `CalibrationView` | `PostureBuddy/CalibrationView.swift` | Guided calibration window, driven entirely by the tracker's `calibrationState` (idle → record good → transition → record bad → complete → Save/Discard). |
| `PostureBuddyApp` | `PostureBuddy/PostureBuddyApp.swift` | `@main`. `MenuBarExtra` (window style) + the calibration `Window` scene + first-run auto-open of calibration. |

### Data flow (one loop)

`CMHeadphoneMotionManager` sample → validate + low-pass →
`AirPostureSnapshot` published → `AppModel` sink →
`PostureMonitor.ingest(quality, connectionState, now)` →
`petState` change → overlay `show()` / `hide()`.

The sensitivity slider and calibration both write the same value:
`tracker.configuration.poorPostureThreshold` + `AppSettings` (persisted).

---

## 3. Key behaviors & timings

| Behavior | Value | Where |
|---|---|---|
| Slouch grace before nag | **5.0 s** sustained `.poor` | `PostureMonitor.slouchGraceSeconds` |
| Recovery before dismiss | **2.0 s** sustained `.good` | `PostureMonitor.recoverySeconds` |
| Poor-posture rule | `pitch − offset < threshold` | core `updateSnapshot()` |
| Default threshold | **−22°** (uncalibrated) | `AirPostureConfiguration.default` |
| Threshold bounds | **−35° … −5°** (slider + calibration clamp) | `AppModel.thresholdRange` |
| Slider direction | −35 = Relaxed, −5 = Strict | `MenuBarContentView` |
| GIF | 1280×720, 54 frames, ~3.6 s, transparent background | `Resources/posturebuddy.gif` |
| GIF playback | Once per appearance, holds last frame | `GIFPlayerView.playOnce()` |
| Bubble timing | appears **1 s before** the GIF ends | `bubbleLeadIn` |
| Pet size / position | ≤360 pt tall, bottom-right, 20% bled off the right edge | overlay tunables |
| Disconnect / pause | pet hides immediately | `PostureMonitor.reset()` |

**Overlay tunables** (top of `PetOverlayWindowController.swift`): `maxGifHeight`,
`bubbleHeadroom`, `bubbleLeadIn`, `bubbleHeadFractionX`, `rightBleedFraction`,
`bottomMargin`.

**Hysteresis details** (all unit-tested): a brief good-posture blip mid-slouch
*resets* the 5 s grace timer; a brief slouch blip mid-recovery *resets* the 2 s
recovery timer; boundary comparisons are `>=`.

**Design decision — tracker always runs:** toggling "Monitor my posture" off stops
*nagging* but not motion tracking, because the menu-bar connection status must stay
live. `PostureMonitor` simply ignores samples while paused.

---

## 4. Build, run, test

```bash
cd PostureBuddy
xcodegen generate                 # project.yml is the source of truth
open PostureBuddy.xcodeproj       # then Run  — or:
xcodebuild -scheme PostureBuddy -destination 'platform=macOS' build
```

Tests (10 app tests + 8 vendored-core tests):

```bash
xcodebuild test -scheme PostureBuddy -destination 'platform=macOS'
cd AirPostureCore && swift test
```

Notes:
- The `.xcodeproj` is **generated** (git-ignored). Always `xcodegen generate`
  after changing `project.yml` or adding files.
- `Info.plist` keys (`LSUIElement`, `NSMotionUsageDescription`, versions) are
  declared in `project.yml` → `info.properties`, so regeneration is idempotent.
- Simulate first run: `defaults delete com.example.posturebuddy`.
- **Troubleshooting "Missing package product 'AirPostureCore'"** in Xcode: stale
  package cache. Quit Xcode, `rm -rf ~/Library/Developer/Xcode/DerivedData/PostureBuddy-*`,
  `xcodegen generate`, reopen. (File ▸ Packages ▸ Reset Package Caches also works.)

### Testing strategy

- **Unit-tested (deterministic):** `PostureMonitor` (8 tests — all hysteresis
  transitions, timer resets, disconnect/pause) via injected timestamps, and
  `AppSettings` (2 tests — default fallback, persistence round-trip) via isolated
  `UserDefaults` suites. The core package has its own 8 tests using
  `MockHeadphoneMotionProvider`.
- **Manually verified (needs real AirPods + GUI):** pet appearance/dismissal,
  focus/click-through behavior, calibration walkthrough, slider feel.

---

## 5. Project layout

```
posturebuddy/                        (git repo root)
├── PostureBuddy/                    the app — fully self-contained
│   ├── project.yml                  XcodeGen manifest (app + test targets)
│   ├── README.md                    quick-start readme
│   ├── DOCUMENTATION.md             this document
│   ├── AirPostureCore/              vendored SPM package (engine) + LICENSE
│   │   ├── Package.swift
│   │   ├── Sources/AirPostureCore/  AirPostureTracker, Types, MotionProvider
│   │   └── Tests/AirPostureCoreTests/
│   ├── PostureBuddy/                app sources (see component table)
│   │   └── Resources/posturebuddy.gif
│   ├── PostureBuddyTests/           PostureMonitorTests, AppSettingsTests
│   └── assets/                      (untracked) source gif/mp4 media
├── docs/superpowers/                design spec + implementation plan (history)
└── .superpowers/sdd/                task-by-task build ledger (history)
```

---

## 6. How it was built (history)

Built 2026-07-08/09 via a spec → plan → task-by-task workflow, each task
implemented TDD-first where testable and independently code-reviewed, plus a
final whole-branch review. Highlights of what the reviews caught and fixed:

- XcodeGen was silently regenerating (wiping) the hand-written `Info.plist` →
  moved keys into `info.properties`.
- The pet originally "popped" instead of animating (SwiftUI `.animation` can't
  fire across remounted hosting views) → moved animation to AppKit.
- Inverted "Strict/Relaxed" slider labels (threshold math direction).
- A main-actor isolation hole in an animation completion handler.
- Calibration results weren't clamped to the slider range.

Evolution of the pet: SF Symbol placeholder + drawn speech bubble → animated GIF
(opaque) → **transparent GIF** walking in from the right corner → play-once with
freeze-frame → bubble timed to the end of the walk (1 s lead-in).

A performance pass then removed ~40 Hz idle SwiftUI re-evaluation (guard
`@Published` writes), a redundant `RunLoop.main` hop that could stall ingestion
during slider drags, ~190 MB of ImageIO frame caching (`shouldCache: false`),
and per-sample copy-on-write of an unused 50-sample pitch-history buffer.

---

## 7. Privacy, footprint, licensing

- **Privacy:** motion data never leaves the device; no network calls, no
  analytics, no camera. The only permission used is headphone motion
  (`NSMotionUsageDescription`).
- **Footprint:** menu-bar-only (`LSUIElement`), one floating panel when nagging;
  GIF decoding holds ~one 1280×720 frame at a time; UI invalidates only on real
  state changes.
- **Licensing:** the vendored `AirPostureCore` engine is used under the **MIT
  license** — the copyright/permission notice at `AirPostureCore/LICENSE` must
  remain with the code. App-level code has no other third-party dependencies.

## 8. Known limitations / future ideas

- Detection is head-pitch only — it can't distinguish "looking down at a book"
  from slouching (mitigated by the 5 s grace period and calibration).
- The pet appears on the **main display** only (multi-monitor picks `NSScreen.main`).
- First-run calibration opens on first *menu open*, not raw process launch.
- No launch-at-login yet; no escalation (bigger nag if you ignore it); no
  posture stats/history. An `AppModel`-level integration test (mock motion
  provider → pet state) is a noted follow-up.
