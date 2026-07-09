# PostureBuddy

A macOS menu-bar app that watches your posture through your AirPods and sends a
friendly pet to nag you when you slouch.

## How it works

PostureBuddy uses the **AirPostureCore** engine — a self-contained Swift package
vendored into this project (`AirPostureCore/`, MIT licensed) — to read AirPods
head-tilt via `CMHeadphoneMotionManager`. When your head
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

- The pet uses **placeholder SF Symbol art**. Swap `PetView.swift`'s `Image` for
  real sprites when available.
- `AirPostureCore` is vendored locally at `AirPostureCore/` (a self-contained SPM
  package, MIT licensed) and referenced by `project.yml`; this project has no
  external project dependencies.
- Depends on nothing over the network; no analytics.

## Credits

The AirPods head-tracking and posture-scoring engine is **AirPostureCore** by
**Allen Lee**, from the open-source [AirPosture](https://github.com/allenv0/AirPosture)
iOS app (MIT license — see `AirPostureCore/LICENSE`). Thanks for open-sourcing it.
