# PostureBuddy

A macOS menu-bar app that watches your posture through your AirPods. When you
slouch, a pixel-art version of *you* walks onto your screen and tells you to sit
straight.

<p align="center">
  <img src="assets/demo.gif" alt="A pixel-art character walking in from the right to remind you to sit straight" width="480">
</p>

<p align="center">
  <em>Slouch for 5 seconds and your pixel self walks in from the corner of your screen.</em>
</p>

## How it works

PostureBuddy uses the **AirPostureCore** engine — a self-contained Swift package
vendored into this project (`AirPostureCore/`, MIT licensed) — to read AirPods
head-tilt via `CMHeadphoneMotionManager`. When your head stays tilted past your
calibrated threshold for ~5 seconds, your pixel-art character walks in from the
bottom-right corner of your screen, stops, and holds up a **"Sit straight!"**
speech bubble. It waits there — click-through, never stealing focus — until you've
held good posture for a couple of seconds, then fades away.

## Requirements

- macOS 14+
- AirPods with head tracking (AirPods Pro, AirPods 3rd gen+, AirPods Max, or
  compatible Beats)
- Xcode 16+, XcodeGen (`brew install xcodegen`)

## Build & run

```bash
xcodegen generate
open PostureBuddy.xcodeproj   # then Run, or:
xcodebuild -scheme PostureBuddy -destination 'platform=macOS' build
```

## Test

```bash
xcodebuild test -scheme PostureBuddy -destination 'platform=macOS'   # 10 app tests
(cd AirPostureCore && swift test)                                    # 8 engine tests
```

## Menu

- **Monitor my posture** — pause/resume nagging
- **Sensitivity** — adjust the head-tilt threshold (Strict ↔ Relaxed)
- **Recalibrate…** — re-run the guided good/slouch calibration
- **Quit**

## Notes

- **Make it look like you.** The character is just an animated GIF bundled at
  `PostureBuddy/Resources/posturebuddy.gif` (source art in `assets/`). Swap in a
  pixel-art GIF of yourself and it works: `GIFPlayerView` reads the frame count and
  delays from the GIF, and the speech bubble is timed off its duration. Use a
  **transparent background** so the character floats on your desktop; have it walk
  in from the right and end standing, since it plays once and holds the last frame.
  Layout knobs are at the top of `PetOverlayWindowController.swift`.
- `AirPostureCore` is vendored locally at `AirPostureCore/` (a self-contained SPM
  package, MIT licensed) and referenced by `project.yml`; this project has no
  external project dependencies.
- Depends on nothing over the network; no analytics.

## Credits

The AirPods head-tracking and posture-scoring engine is **AirPostureCore** by
**Allen Lee**, from the open-source [AirPosture](https://github.com/allenv0/AirPosture)
iOS app (MIT license — see `AirPostureCore/LICENSE`). Thanks for open-sourcing it.
