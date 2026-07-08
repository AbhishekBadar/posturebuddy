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
