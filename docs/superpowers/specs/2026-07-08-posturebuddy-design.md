# PostureBuddy — Design

**Date:** 2026-07-08
**Status:** Approved (design)

## Overview

PostureBuddy is a native **macOS menu-bar app** that detects poor posture using AirPods
head-tracking and nudges the user with an animated on-screen **posture pet**.

It reuses the existing `AirPostureCore` Swift package (from the sibling `AirPosture`
project) as its head-tracking + posture-scoring engine. When the user slouches for a
sustained few seconds, a pet character slides into a screen corner with a "Sit up
straight!" speech bubble; it automatically walks off once posture is corrected. A
first-run guided calibration personalizes the posture threshold.

New folder: **`PostureBuddy/`** at the repo root (PascalCase, matching the sibling
`AirPosture/`).

## Goals

- Detect poor head posture via AirPods with zero manual effort during normal use.
- Deliver a gentle, charming, non-blocking nudge (corner pet) — not an intrusive overlay.
- Personalize the "bad posture" threshold via quick guided calibration, adjustable later.
- Reuse `AirPostureCore` rather than reimplementing motion/posture logic.

## Non-Goals (YAGNI — explicitly out of scope)

- Session history, analytics, or trend reporting.
- OS notifications, sounds, or haptics.
- Stretch coaching / body tracking (ARKit).
- iOS support.
- Polished final character art (placeholder sprites for now).
- Live Activities / Dynamic Island / APNs relay.

## Detection & Behavior (decisions locked in brainstorming)

- **Detection:** AirPods head tracking via `AirPostureCore`.
- **Platform:** native macOS menu-bar app (SwiftUI), reusing `AirPostureCore`.
- **Graphic:** a corner character/pet with a speech bubble.
- **Timing:** appears only after **sustained slouch**, and **auto-dismisses** once
  posture is corrected (with hysteresis to avoid flicker).
- **Calibration:** first-run guided calibration (`sit up straight` → `slouch`), plus an
  adjustable sensitivity control afterward.
- **Art:** placeholder sprites now (two poses), real art swapped in later.

## Architecture / Components

Each unit has one clear responsibility and a well-defined interface.

### 1. `AirPostureCore` (reused dependency — unchanged)
- Referenced as a **local SPM package by relative path** (`../AirPosture/AirPostureCore`).
- No modifications to the package.
- Provides `AirPostureTracker` (`ObservableObject`, publishes `AirPostureSnapshot`),
  `CMHeadphoneMotionProvider` (wraps `CMHeadphoneMotionManager`, macOS 14+),
  `MockHeadphoneMotionProvider` (tests), calibration API, and `AirPostureConfiguration`.
- **Tradeoff:** this couples `PostureBuddy/` to its sibling `AirPosture/` on disk.
  Accepted in favor of staying DRY. Alternative (vendoring a copy) rejected for now.

### 2. `PostureMonitor` (the brain)
- Wraps an `AirPostureTracker` and subscribes to its `snapshot`.
- Applies **sustained-slouch debounce / hysteresis**:
  - `.poor` quality must persist ≥ `slouchGraceSeconds` (default **5s**) before it
    emits a nag.
  - `.good` quality must persist ≥ `recoverySeconds` (default **2s**) before it clears
    the nag.
- Publishes a simple `PetState` enum: `.hidden` / `.nagging`.
- Also surfaces connection status derived from `snapshot.connectionState`.
- All timing/hysteresis logic lives here so it is independently testable.

### 3. `PetOverlayWindow`
- A borderless, transparent, **non-activating** `NSPanel` at floating window level,
  configured to join all Spaces and never steal focus (analogous to Hydrate Buddy's
  `showInactive`).
- Pinned to the **bottom-right** corner of the active screen; recomputes position on
  screen/Space changes.
- Hosts the SwiftUI `PetView`.

### 4. `PetView` (SwiftUI)
- Renders the pet and its speech bubble.
- Animations: **walk-in → idle-nag → walk-out**, driven by `PetState`.
- Uses **placeholder sprites** with two poses (neutral, slouch-alert).

### 5. `MenuBarController` (`MenuBarExtra`)
- Menu-bar icon + menu:
  - Connection status ("AirPods connected" / "AirPods not connected").
  - Start / Pause monitoring.
  - Recalibrate…
  - Sensitivity slider (adjusts threshold).
  - Launch at login (packaged behavior).
  - Quit.

### 6. `CalibrationController` + `CalibrationView`
- A normal (focusable) window that drives `AirPostureTracker.beginCalibration()`.
- Flow: "Sit up straight" (record good) → "Now slouch" (record bad) →
  `saveCalibrationResult()` → persist resulting threshold.
- Can be launched on first run and re-run anytime from the menu.

### 7. `Settings` / persistence
- Stores calibrated `poorPostureThreshold` and a sensitivity offset in `UserDefaults`.
- On launch, applies stored threshold to `tracker.configuration`; falls back to
  `AirPostureConfiguration.default` (−22°) when no calibration exists yet.

## Data Flow

```
CMHeadphoneMotionProvider
  → AirPostureTracker.snapshot (quality, adjustedPitchDegrees, connectionState, ...)
    → PostureMonitor (debounce / hysteresis)
      → PetState (.hidden / .nagging)
        → PetOverlayWindow + PetView (walk-in / nag / walk-out)
```

- The **sensitivity slider** and **calibration result** both write
  `tracker.configuration.poorPostureThreshold`.

## Edge Cases

- **No AirPods / disconnected:** pet stays hidden; menu shows "AirPods not connected"
  (driven by `snapshot.connectionState`).
- **AirPods removed mid-nag:** pet walks off.
- **Not yet calibrated:** use `AirPostureConfiguration.default` (−22°).
- **Multiple displays / Space switches:** panel appears on the active Space; corner
  position recomputed on screen change.
- **Monitoring paused:** no pet regardless of posture.

## Build & Testing

- **Build system:** XcodeGen `project.yml` (consistent with `AirPosture/`), macOS 14
  deployment target, references the local `AirPostureCore` package by relative path.
- **Unit tests:** cover `PostureMonitor` debounce/hysteresis using
  `MockHeadphoneMotionProvider` — feed pitch sample sequences with timestamps and assert
  `PetState` transitions and their timing (grace + recovery windows).
- **Manual verification:** run the app; confirm pet appears after sustained slouch,
  walks off on recovery, respects pause, and handles AirPods disconnect. Calibration flow
  verified end-to-end.

## Open Follow-ups (post-MVP, not now)

- Replace placeholder sprites with polished character art.
- Optional escalation (mild → strong) if slouch persists.
- Optional stats / streaks.
