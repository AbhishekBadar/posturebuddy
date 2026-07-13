# PostureBuddy — Project Documentation

A native macOS **menu-bar app** that watches your sitting posture through your
**AirPods** and, when you slouch, sends a **pixel-art version of you** walking onto
your screen, yells, and roasts your posture — then fades out once you've corrected
yourself.

The character is just a bundled GIF, so anyone can drop in a pixel avatar of
themselves (see §7).

No camera, no network, no analytics. Everything runs locally.

---

## 1. How it works (user's view)

1. **Launch** — PostureBuddy appears only in the menu bar (no Dock icon). On the
   very first run it opens a guided calibration window.
2. **Calibration** — you sit up straight for ~5 s, then slouch for ~5 s. The app
   computes a personalized head-tilt threshold from the two averages and saves it.
3. **Monitoring** — with AirPods in, the app continuously reads your head pitch.
   - Slouch past your threshold and *stay* slouched for **5 seconds** → your pixel-art
     character appears bottom-right: it **walks in from the right edge, stops, stands**.
     ~1 s before the walk ends, a **speech bubble** pops up with a random roast
     ("Gravity: 1. You: 0.") and the **sound effect plays on the same beat**. The
     character then stays frozen, staring at you.
   - Sit up straight and *hold it* for **2 seconds** → the character fades out.
4. **Menu bar** — click the icon for: connection status, a **Monitor my posture**
   toggle, a **Play sound** toggle, a **Sensitivity** slider (Relaxed ↔ Strict),
   **Recalibrate…**, and Quit.

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
┌─────────────────────────┐   app target (PostureBuddy/Motion/)
│  CMHeadphoneMotionSource │  wraps CMHeadphoneMotionManager
└──────────┬──────────────┘
           ▼
┌─────────────────────────┐
│ PostureTracker           │  validates samples, low-pass filters pitch,
│  + PostureEngine         │  classifies good/poor vs threshold, tracks
│ (@MainActor, Combine)    │  connection health, runs calibration
└──────────┬──────────────┘
           │  @Published PostureSnapshot (quality, connection, …)
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
│   ├─ SpeechBubbleView     │  random roast, timed to the GIF
│   └─ SoundPlayer         │  sound effect, fires with the bubble
└──────────────────────────┘
```

### Components

| Unit | File | Responsibility |
|---|---|---|
| `PostureEngine` | `PostureBuddy/Motion/PostureEngine.swift` | Pure, time-injected posture engine: sample validation, low-pass pitch filter (factor 0.4), good/poor classification (`pitch < threshold` → poor), connection freshness, guided calibration. Fully unit-tested with injected dates. |
| `PostureTracker` / `CMHeadphoneMotionSource` | `PostureBuddy/Motion/` | `@MainActor` glue: wraps `CMHeadphoneMotionManager`, forwards samples to the engine, owns the 2 s health tick and the 0.1 s calibration-progress tick, publishes `PostureSnapshot` on every sample. |
| `AppModel` | `PostureBuddy/AppModel.swift` | Central coordinator. Applies the persisted threshold, subscribes to tracker snapshots, feeds `PostureMonitor`, drives the overlay from `PetState`, exposes menu state, and orchestrates calibration (pause nags → run → clamp + save result). |
| `PostureMonitor` | `PostureBuddy/PostureMonitor.swift` | The nag decision. Pure, injectable-time hysteresis: `.poor` sustained ≥ **5 s** → `.nagging`; then `.good` sustained ≥ **2 s** → `.hidden`. Any disconnect or pause instantly hides and resets. Fully unit-tested. |
| `PetState` | `PostureBuddy/PetState.swift` | Two-case enum: `.hidden` / `.nagging`. |
| `AppSettings` | `PostureBuddy/AppSettings.swift` | `UserDefaults` persistence for `poorPostureThreshold` (defaults to −22°), `hasCalibrated`, and `soundEnabled` (defaults to on). Unit-tested. |
| `PetOverlayWindowController` | `PostureBuddy/PetOverlayWindowController.swift` | The on-screen character. Borderless, transparent, **non-activating**, **click-through** `NSPanel` (floating level, joins all Spaces, works over full-screen apps). Positions bottom-right with the character entering from the screen edge. Fades in/out; schedules the speech bubble. |
| `GIFPlayerView` | `PostureBuddy/GIFPlayerView.swift` | Custom `NSImageView` that plays the GIF **exactly once and freezes on the last frame** (no looping). Decodes frames on demand with `shouldCache: false` (~one frame in memory). Exposes `totalDuration` from real frame delays. |
| `SpeechBubbleView` | `PostureBuddy/SpeechBubbleView.swift` | SwiftUI white rounded bubble + tail holding the nag line (the GIF art has no text of its own). Wraps at 300 pt, so the overlay grows its headroom to fit two-line messages. |
| `NagMessages` | `PostureBuddy/NagMessages.swift` | The pool of sassy lines. `next()` picks at random but never repeats the same line back-to-back. Unit-tested. |
| `SoundPlayer` | `PostureBuddy/SoundPlayer.swift` | Retains a prepared `AVAudioPlayer` for `faaah.mp3` and restarts it from 0 on each play. Retention matters — a player that falls out of scope stops instantly. |
| `MenuBarContentView` | `PostureBuddy/MenuBarContentView.swift` | Menu-bar popover UI: status, monitor toggle, sound toggle, sensitivity slider (−35…−5°), Recalibrate…, Quit. |
| `CalibrationView` | `PostureBuddy/CalibrationView.swift` | Guided calibration window, driven entirely by the tracker's `calibrationState` (idle → record good → transition → record bad → complete → Save/Discard). |
| `PostureBuddyApp` | `PostureBuddy/PostureBuddyApp.swift` | `@main`. `MenuBarExtra` (window style) + the calibration `Window` scene + first-run auto-open of calibration. |

### Data flow (one loop)

`CMHeadphoneMotionManager` sample → validate + low-pass →
`PostureSnapshot` published → `AppModel` sink →
`PostureMonitor.ingest(quality, connectionState, now)` →
`petState` change → overlay `show()` / `hide()`.

The sensitivity slider and calibration both write the same value:
`tracker.threshold` + `AppSettings` (persisted).

---

## 3. Key behaviors & timings

| Behavior | Value | Where |
|---|---|---|
| Slouch grace before nag | **5.0 s** sustained `.poor` | `PostureMonitor.slouchGraceSeconds` |
| Recovery before dismiss | **2.0 s** sustained `.good` | `PostureMonitor.recoverySeconds` |
| Poor-posture rule | `filteredPitch < threshold` | `PostureEngine.snapshot` |
| Default threshold | **−22°** (uncalibrated) | `PostureEngine.defaultThreshold` |
| Threshold bounds | **−35° … −5°** (slider + calibration clamp) | `PostureEngine.thresholdRange` |
| Slider direction | −35 = Relaxed, −5 = Strict | `MenuBarContentView` |
| GIF | 1280×720, 54 frames, ~3.6 s, transparent background | `Resources/posturebuddy.gif` |
| GIF playback | Once per appearance, holds last frame | `GIFPlayerView.playOnce()` |
| Bubble timing | appears **1 s before** the GIF ends | `bubbleLeadIn` |
| Sound | `faaah.mp3` (~1.9 s), fires **with** the bubble; mutable from the menu | `SoundPlayer`, `AppSettings.soundEnabled` |
| Nag line | random from `NagMessages.all`, never repeating consecutively | `NagMessages.next()` |
| Character size / position | ≤360 pt tall, bottom-right, 20% bled off the right edge | overlay tunables |
| Disconnect / pause | character hides immediately | `PostureMonitor.reset()` |

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

All commands run from the repository root.

```bash
xcodegen generate                 # project.yml is the source of truth
open PostureBuddy.xcodeproj       # then Run  — or:
xcodebuild -scheme PostureBuddy -destination 'platform=macOS' build
```

Tests (35 tests):

```bash
xcodebuild test -scheme PostureBuddy -destination 'platform=macOS'
```

Notes:
- The `.xcodeproj` is **generated** (git-ignored). Always `xcodegen generate`
  after changing `project.yml` or adding files.
- `Info.plist` keys (`LSUIElement`, `NSMotionUsageDescription`, versions) are
  declared in `project.yml` → `info.properties`, so regeneration is idempotent.
- Simulate first run: `defaults delete com.example.posturebuddy`.

### Testing strategy

- **Unit-tested (deterministic):** `PostureEngine` (16 tests — sample validation,
  filter, quality classification, connection lifecycle, calibration
  walkthrough/clamping) and `PostureTracker` (4 tests — idempotent start,
  publish-per-sample invariant) via injected dates and a fake motion source;
  `PostureMonitor` (8 tests — all hysteresis transitions, timer resets,
  disconnect/pause) via injected timestamps; `AppSettings` (4 tests — threshold
  default/round-trip, sound-enabled default/round-trip) via isolated
  `UserDefaults` suites; and `NagMessages` (3 tests — no consecutive repeats,
  every line reachable).
- **Manually verified (needs real AirPods + GUI):** character appearance/dismissal,
  focus/click-through behavior, the sound firing on the same beat as the bubble,
  calibration walkthrough, slider feel.

---

## 5. Project layout

```
posturebuddy/                        (git repo root = the project)
├── project.yml                      XcodeGen manifest (app + test targets)
├── README.md                        quick-start readme
├── DOCUMENTATION.md                 this document
├── PostureBuddy/                    app sources (see component table)
│   ├── Motion/                      PostureEngine, PostureTracker, CMHeadphoneMotionSource
│   └── Resources/                   posturebuddy.gif (character), faaah.mp3 (sound)
├── PostureBuddyTests/               PostureEngineTests, PostureTrackerTests,
│                                    PostureMonitorTests, AppSettingsTests
├── assets/                          posturebuddy.gif (art source of truth)
│                                    demo.gif (README preview, opaque bg)
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
- The character originally "popped" instead of animating (SwiftUI `.animation` can't
  fire across remounted hosting views) → moved animation to AppKit.
- Inverted "Strict/Relaxed" slider labels (threshold math direction).
- A main-actor isolation hole in an animation completion handler.
- Calibration results weren't clamped to the slider range.

Evolution of the character: SF Symbol placeholder + drawn speech bubble → animated GIF
(opaque) → **transparent GIF** walking in from the right corner → play-once with
freeze-frame → bubble timed to the end of the walk (1 s lead-in).

A performance pass then removed ~40 Hz idle SwiftUI re-evaluation (guard
`@Published` writes), a redundant `RunLoop.main` hop that could stall ingestion
during slider drags, ~190 MB of ImageIO frame caching (`shouldCache: false`),
and per-sample copy-on-write of an unused 50-sample pitch-history buffer.

---

## 7. Customizing the character

The character is not hardcoded — it's a single animated GIF at
`PostureBuddy/Resources/posturebuddy.gif` (source art kept in `assets/`). To make
it a pixel-art version of *you*, replace that file. Nothing else needs to change:
`GIFPlayerView` reads the frame count and per-frame delays from the GIF itself, and
`PetOverlayWindowController` times the speech bubble off the GIF's own duration.

For it to look right, the GIF should:

- have a **transparent background** — otherwise it renders as an opaque rectangle
  on your desktop instead of a character standing on it;
- **walk in from the right and end standing**, because the GIF is played exactly
  once per nag and then freezes on its final frame;
- keep a **16:9-ish canvas** with the character roughly centered — the overlay
  assumes `gifAspect` (default `1280/720`) and bleeds the empty right portion of
  the canvas off the screen edge so the character enters from the corner.

If your GIF has different proportions, adjust the tunables at the top of
`PetOverlayWindowController.swift`: `gifAspect`, `maxGifHeight` (character size),
`rightBleedFraction` (how far into the corner it enters), `bubbleHeadFractionX`
(bubble position over the head), `bubbleHeadroom`, `bubbleLeadIn` (how long before
the walk ends the bubble appears), and `bottomMargin`.

**What it says** lives in `NagMessages.all` — edit the array. **What it sounds like**
is `PostureBuddy/Resources/faaah.mp3`; replace the file (any format `AVAudioPlayer`
reads) or update the resource name in `PetOverlayWindowController`'s `SoundPlayer`
initializer. Keep it short — it fires on the same beat as the bubble, roughly a
second before the character stops moving.

---

## 8. Privacy, footprint, licensing

- **Privacy:** motion data never leaves the device; no network calls, no
  analytics, no camera. The only permission used is headphone motion
  (`NSMotionUsageDescription`).
- **Footprint:** menu-bar-only (`LSUIElement`), one floating panel when nagging;
  GIF decoding holds ~one 1280×720 frame at a time; UI invalidates only on real
  state changes.
- **Dependencies:** none — the posture engine is part of the app; no
  third-party code.

## 9. Known limitations / future ideas

- Detection is head-pitch only — it can't distinguish "looking down at a book"
  from slouching (mitigated by the 5 s grace period and calibration).
- The character appears on the **main display** only (multi-monitor picks `NSScreen.main`).
- First-run calibration opens on first *menu open*, not raw process launch.
- No launch-at-login yet; no escalation (bigger nag if you ignore it); no
  posture stats/history. An `AppModel`-level integration test (mock motion
  provider → character state) is a noted follow-up.
