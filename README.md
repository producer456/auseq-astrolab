# AUSeq

A basic MIDI sequencer + **AUv3** plugin host for **iPad Pro 11" (M5)**, controlled by an **Arturia KeyLab mk2 88**.

Native Swift / SwiftUI / `AVAudioEngine`. iPad-only. On iOS, "AU plugins" means **AUv3** (Audio Unit v3 app extensions) — desktop AU/VST do not load.

## What works today (code-complete, compiles; on-device verification pending signing)

- **Multi-track AUv3 hosting** — each track loads an installed AUv3 instrument out-of-process into the audio graph, with per-track volume/mute.
- **Live play** — on-screen multi-touch keyboard *and* any connected MIDI input (the KeyLab over USB) route to the **selected** track.
- **Per-track parameters & presets** — selecting a track shows that plugin's parameter sliders, its factory-preset menu, and its **own native plugin UI** embedded.

## Roadmap

| # | Milestone | Status |
|---|-----------|--------|
| M0 | Project scaffold | ✅ builds |
| M1 | Audio engine + AUv3 hosting | ✅ code complete |
| M2 | CoreMIDI input → selected track | ✅ code complete |
| M3 | Multi-track model + switching | ✅ code complete |
| M4 | Parameter view + preset switching | ✅ code complete |
| M5 | KeyLab DAW-port MCU integration (faders/encoders/transport/LCD) | ⬜ next (needs hardware) |
| M6 | Sequencer record/playback + transport + loop | ⬜ |
| M7 | Touch piano-roll editor | ⬜ |

> Everything M1–M4 compiles for the simulator but has **not run on the iPad yet** — see Signing below.

## Build & run

Requires macOS + Xcode 16/26, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (the repo ignores the generated `.xcodeproj`).

```bash
# 1. Generate the Xcode project from project.yml
scripts/generate.sh

# 2a. Compile-check against the simulator (no signing needed)
scripts/build-sim.sh

# 2b. Build + install to the iPad ("Paddy")
scripts/deploy.sh
```

Or open it in Xcode after `scripts/generate.sh`:

```bash
open AUSeq.xcodeproj
```

## Signing (one-time)

On-device install needs an Apple ID logged into Xcode (the dev certificate alone is not enough — Xcode must be able to create a provisioning profile).

1. Xcode → **Settings → Accounts → +** → sign in with the team Apple ID (David Sheffield, team `578Y4PB742`).
2. After that, `scripts/deploy.sh` builds, signs, and installs to the iPad with no further GUI steps.

This is a personal **development / sideload** install — nothing is published to the App Store.

## Layout

```
project.yml                 # XcodeGen project definition
Sources/
  App/                      # App entry + root ContentView
  Audio/                    # AudioEngine (multi-track host), AUComponentBrowser
  MIDI/                     # MIDIManager (CoreMIDI input, UMP parsing)
  Model/                    # Track, AppModel
  UI/                       # Keyboard, track list, parameter/preset UI, plugin UI embed
scripts/                    # generate / build-sim / deploy
CLAUDE.md                   # resume notes for Claude Code
```
