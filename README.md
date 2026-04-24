
 # MacKnock Pro 🤜💻

Detect physical knocks on your MacBook and trigger system actions like media play/pause, skip, lock screen, and more.

Uses the Apple Silicon **MEMS accelerometer** (Bosch BMI286 IMU) via the undocumented IOKit HID interface for real-time vibration detection.

<p align="center">
  <img src="assets/popover.png" width="400" alt="MacKnock Pro Popover">
</p>


## Features

- 🎵 **Media Control** — Play/Pause, Next Track, Previous Track, Volume Up/Down, Mute
- 🔒 **System Actions** — Lock Screen, Screenshot, Do Not Disturb
- 🤖 **Custom Actions** — Launch Apps, Run Shortcuts, Execute Shell/AppleScript
- 🎯 **Multi-Knock Patterns** — Double, Triple, and Quad knock recognition
- 📊 **Live Waveform Monitor** — Real-time accelerometer data visualization
- ⚙️ **Sensitivity Profiles** — Sensitive, Balanced, Strong, Fast presets
- 🎨 **Premium UI** — Beautiful menu bar popover and settings window

![Actions Settings](settings-actions.png)

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon Mac (M2, M3, M4, M5 — **not** M1 base models)
- Root privileges (`sudo`) for accelerometer access

> **Note**: This app uses undocumented IOKit HID interfaces and cannot be distributed on the Mac App Store.

## How It Works

1. **IOKit HID Bridge** — Opens `AppleSPUHIDDevice` on vendor usage page `0xFF00`, usage `3` (accelerometer)
2. **Raw HID Reports** — Parses 22-byte reports with int32 x/y/z at byte offset 6, scaled by `/65536` for g-force
3. **Knock Detection** — Runs 4 algorithms in parallel:
   - **STA/LTA** (Short-Term/Long-Term Average) at 3 timescales
   - **CUSUM** (Cumulative Sum) for mean-shift detection
   - **Kurtosis** for impulsive signal detection (knock = kurtosis > 6)
   - **Peak/MAD** (Median Absolute Deviation) for outlier detection
4. **Pattern Recognition** — Buffers knocks to detect double, triple, and quad patterns
5. **Action Execution** — Maps patterns to configurable system actions

![Vibration Monitor](settings-monitor.png)

## Understanding Sensitivity Profiles & Sliders

MacKnock Pro uses an adaptive machine-learning threshold engine to learn how hard you hit your Mac, but you can manually tune its baseline behavior using **Profiles** and **Sliders** in the **Sensitivity** tab.

![Sensitivity Profiles](settings-sensitivity.png)

### Sensitivity Profiles
These are pre-configured presets that change both the force required to trigger a knock and the time window allowed between knocks.

- **Sensitive** (0.03g / 600ms): Detects light taps and gentle touches. Best if you type lightly and want effortless triggering, but may cause false positives if you type heavily.
- **Balanced** (0.08g / 750ms): The default sweet spot. Responds to firm knocks while ignoring normal typing vibrations and trackpad clicks.
- **Strong** (0.20g / 1000ms): Only responds to hard, deliberate knocks. You have to physically thump the chassis. Best if you are a very heavy typist or use a mechanical keyboard on the same desk.
- **Fast** (0.10g / 350ms): Quick response with a very short cooldown. Designed for users who enter their double/triple knocks very rapidly.

### Fine Tuning Sliders
If the presets don't feel right, you can adjust the underlying math directly:

- **Noise Guard Floor (Amplitude):** 
  This sets the absolute minimum g-force (acceleration) required for a vibration to be considered a knock. The adaptive ML engine cannot drop the threshold below this value. 
  - *Slide Left (Allow Soft Taps):* Lowers the floor (e.g., 0.01g). The app will pick up very subtle finger taps.
  - *Slide Right (Hard Knocks Only):* Raises the floor (e.g., 0.20g). The app will completely ignore light taps, heavy typing, and desk bumps.

- **Cooldown Period (Time Window):**
  This dictates how long the app waits (in milliseconds) after your first knock to see if you are going to knock again (to form a Double, Triple, or Quad pattern). 
  - *Slide Left (Fast Response):* Short window (e.g., 300ms). You must tap very quickly. The benefit is that actions trigger almost instantly after your final tap.
  - *Slide Right (Slow Response):* Long window (e.g., 1000ms). Allows you to pace your knocks slowly and casually. The downside is that the app must wait this entire duration after your final knock before it can "lock in" the pattern and execute your action.

## Building

1. Open `MacKnock Pro.xcodeproj` in Xcode 15+
2. Select the "MacKnock Pro" scheme
3. Build & Run (⌘R)

## Running

The app requires root privileges for accelerometer access:

```bash
sudo /path/to/MacKnock\ Pro.app/Contents/MacOS/MacKnock\ Pro
```

There is currently no built-in privilege escalation flow. If you launch without `sudo`,
the app UI opens but sensor listening will fail with a root-privileges error.

## Credits

- Sensor reading & IOKit interface: [olvvier/apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer)
- Vibration detection algorithms: [taigrr/spank](https://github.com/taigrr/spank)

## Settings

![General Settings](settings-general.png)

## License

MIT
