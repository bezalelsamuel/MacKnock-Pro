# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MacKnock Pro is a macOS menu bar app that detects physical knocks on an Apple Silicon Mac's chassis by reading the built-in MEMS accelerometer via undocumented IOKit HID interfaces. It requires **root privileges** (`sudo`) at runtime to open the `AppleSPUHIDDevice` HID device.

- **Target**: macOS 14.0+, Apple Silicon M2+ (M1 base not supported)
- **Language**: Swift 5.9, SwiftUI
- **Bundle ID**: `com.macknockpro.app`
- **Not App Store compatible** — uses undocumented IOKit APIs and sandbox is disabled

## Build & Run

```bash
# Open in Xcode (requires Xcode 15+)
open "MacKnock Pro.xcodeproj"
# Then build with ⌘R (scheme: MacKnock Pro)

# Run with root (required for accelerometer access):
sudo "/path/to/MacKnock Pro.app/Contents/MacOS/MacKnock Pro"
```

If you want to regenerate the Xcode project from `project.yml`, the project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen):
```bash
xcodegen generate
```

The app silently fails knock detection (but otherwise runs) without `sudo`. `AppState.hasRootPrivileges` (`geteuid() == 0`) is used to surface this in the UI.

## Architecture: The Signal Pipeline

Data flows strictly one-way through five layers:

```
AccelerometerService (IOKit HID, background thread)
  ↓ ax/ay/az samples at ~100Hz
KnockDetector (multi-algorithm detection)
  ↓ KnockEvent (with amplitude, severity, detector sources)
KnockPatternRecognizer (pattern buffering state machine)
  ↓ KnockPatternEvent (double/triple/quad)
ActionExecutor (maps patterns → actions)
  ↓ confirmKnock(amplitude) feedback
AdaptiveThresholdEngine (online GMM, updates knock/noise models)
```

This pipeline is wired in `AppState.setupBindings()` in `MacKnockProApp.swift`.

### Key Components

**`Sensor/IOKitBridge.swift`** — Low-level HID bridge. Reads 22-byte reports from `AppleSPUHIDDevice` on vendor page `0xFF00`, usage `3`. XYZ int32 values start at byte offset 6 and are scaled by `1/65536` to get g-force. `wakeSPUDrivers()` must be called to activate the sensor before reports begin.

**`Sensor/AccelerometerService.swift`** — Wraps `IOKitBridge`, runs the HID run loop on a dedicated background thread, decimates from ~800Hz to ~100Hz, and exposes a callback `setCallback(ax:ay:az:time:)`.

**`Detection/KnockDetector.swift`** — Runs 4 algorithms in parallel on every sample:
1. **STA/LTA** at 3 timescales (fast/medium/slow) — ratio-based onset detection
2. **CUSUM** — cumulative sum for mean shifts
3. **Kurtosis** — impulsive spike detection (threshold: kurtosis > 6)
4. **Peak/MAD** — outlier detection via median absolute deviation

Classification into `KnockSeverity` (.major / .shock / .micro / .vibration / etc.) is based on detector count and amplitude. Only `.major`, `.shock`, and `.micro` are treated as real knocks (`isKnock = true`). A high-pass filter (alpha=0.85) removes gravity/slow tilt before processing.

**`Detection/AdaptiveThresholdEngine.swift`** — Online 2-class Gaussian Mixture Model (noise class vs. knock class). Computes an optimal Fisher linear discriminant threshold between classes. Persists state to `UserDefaults` under key `adaptive_threshold_state_v1`. The effective threshold in `KnockDetector` is `max(adaptiveThreshold.threshold, amplitudeFloor)`.

**`Detection/KnockPattern.swift`** — State machine that buffers up to 4 `KnockEvent`s within timing windows (0.38–0.44s inter-knock gap) and flushes as double/triple/quad patterns. The user-facing cooldown (`patternCooldown`) is enforced here, not in the detector, so intra-pattern knocks aren't blocked.

**`Actions/ActionExecutor.swift`** — Maps `KnockPatternType` → `ActionConfiguration` (stored in `UserDefaults` as JSON under `"patternActions"`). Subscribes to `KnockPatternRecognizer.patternPublisher` via Combine. Actions include media controls, system actions (lock, screenshot, DND), and custom (app launch, Apple Shortcuts, shell scripts).

**`Settings/SettingsManager.swift`** — `@MainActor` singleton using `@AppStorage` for all settings. Changes propagate to the pipeline via `UserDefaults.didChangeNotification` observed in `AppState`.

### Threading Model

- Accelerometer callbacks arrive on a **background HID thread** in `AccelerometerService`
- `KnockDetector.process()` runs on that background thread; thread-safe reads use `OSAllocatedUnfairLock`
- `KnockEvent` and pattern events are dispatched to **`DispatchQueue.main`** before reaching the UI or `ActionExecutor`
- `ActionExecutor` and `AppState` are `@MainActor`
- `AdaptiveThresholdEngine` uses its own `OSAllocatedUnfairLock` for internal state; persistence saves happen on `DispatchQueue.global(qos: .utility)`

### Sleep/Wake Handling

`AppState.setupLifecycle()` observes `NSWorkspace.willSleepNotification` / `didWakeNotification`. On wake, it waits 1 second before restarting the sensor to allow the SPU hardware to reinitialize.
