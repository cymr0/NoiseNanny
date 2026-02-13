# NoiseNanny

macOS menu bar app that enforces volume rules on Sonos speakers using [sonoscli](https://github.com/steipete/sonoscli).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/CYMR0/NoiseNanny/main/scripts/install.sh | bash
```

Downloads the latest pre-built `.app` from GitHub Releases and installs to `/Applications`. No Xcode or Swift needed.

> On first launch, macOS may block the app because it isn't notarized. Right-click the app, choose Open, then click Open in the dialog.

## Features

- **Volume Caps** — Time-window rules (e.g., 10 PM–7 AM, max 20%). Polls speakers and clamps volume if it exceeds the cap.
- **Auto-Stop Playback** — Stops music during a quiet window (e.g., 11 PM–7 AM). Music restarted during the window is stopped again.
- **Speaker Dashboard** — Menu bar dropdown shows all discovered speakers with current volume and playback state.
- **Group/Zone Aware** — Speakers are displayed by Sonos group. Rules can target individual rooms, groups, or all speakers.
- **CLI Auto-Install** — On first launch, downloads the sonoscli binary from GitHub releases if not found.
- **No Dock Icon** — Runs as a pure menu bar accessory (`LSUIElement`).

## Requirements

- macOS 14+ (Sonoma)
- [sonoscli](https://github.com/steipete/sonoscli) — auto-installed on first launch, or `brew install steipete/tap/sonoscli`

## Build from Source

Requires Swift 5.9+ / Xcode 15+.

```bash
git clone https://github.com/CYMR0/NoiseNanny.git
cd NoiseNanny

# Build release + create .app bundle + zip
bash scripts/build.sh

# Install to /Applications
bash scripts/build.sh --install

# Create a GitHub release
gh release create v1.0 .build/NoiseNanny.zip --title "v1.0"
```

## File Structure

| File | Purpose |
|---|---|
| `NoiseNannyApp.swift` | `@main` entry, hides dock icon, sets up menu bar |
| `MenuBarView.swift` | SwiftUI menu bar dropdown UI |
| `SettingsView.swift` | Settings window (schedules, rules, CLI path) |
| `SonosCLI.swift` | Async wrapper around the CLI binary |
| `CLIInstaller.swift` | Downloads/updates sonoscli binary from GitHub |
| `Models.swift` | Speaker, SpeakerGroup, Rule structs, RuleTarget |
| `ScheduleEngine.swift` | Timer-based polling, volume clamping, auto-stop |
| `SettingsStore.swift` | `@Observable` / UserDefaults persistence |

## Acknowledgements

- [sonoscli](https://github.com/steipete/sonoscli) by [@steipete](https://github.com/steipete) — MIT License

## License

[MIT](LICENSE)
