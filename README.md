# Accentum

Native macOS menu bar app for **Sennheiser Accentum** headphones — noise cancellation, transparency, and EQ without the mobile app.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

<p align="center">
  <img src="https://img.shields.io/badge/Noise%20Cancel-✓-lightgrey" />
  <img src="https://img.shields.io/badge/Transparency-✓-lightgrey" />
  <img src="https://img.shields.io/badge/EQ%20Presets-✓-lightgrey" />
  <img src="https://img.shields.io/badge/Auto--connect-✓-lightgrey" />
</p>

## Why this exists

Sennheiser has no official Mac app for Accentum. The mobile **Smart Control** app controls ANC, transparency, and EQ over Bluetooth — this app does the same from your menu bar.

## Features

- **Noise control** — Noise Cancel, Transparency, Off
- **Equalizer** — presets (Rock, Pop, Jazz, …) and per-band sliders
- **Bass Boost**
- **Battery** and codec info
- **Auto-connect** when headphones pair to your Mac
- **Open at Login** (on by default)
- Frosted-glass menu bar UI, no Dock icon

## Supported headphones

Tested on **ACCENTUM Wireless**. The underlying GAIA protocol is shared across recent Sennheiser Qualcomm models (Momentum 4, Accentum Plus, etc.) — they may work but are untested.

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools or Xcode (`swift` on your PATH)
- Sennheiser headphones **paired** in System Settings → Bluetooth

## Install

### From source (recommended)

```bash
git clone https://github.com/jvalaj/accentum.git
cd accentum
chmod +x build_app.sh
./build_app.sh release
cp -R Accentum.app /Applications/
open /Applications/Accentum.app
```

On first launch, allow **Bluetooth** access when macOS asks.

### Optional: verify connection

```bash
./Accentum.app/Contents/MacOS/Accentum --probe
```

## Usage

1. Pair and connect your Accentum in **System Settings → Bluetooth**
2. Click the **headphones** icon in the menu bar
3. Switch modes, change EQ, toggle Bass Boost

**Open at Login** keeps the app ready in the background so it auto-connects when your headphones pair. Toggle it in the menu footer.

> **Tip:** Close the Sennheiser Smart Control app on your phone if connection fails — it can block the GAIA control channel.

## How it works

Sennheiser Accentum headphones speak **Qualcomm GAIA V3** over **Bluetooth Classic RFCOMM** (not BLE). The app:

1. Finds your paired headphones via `IOBluetooth`
2. Opens the GAIA service (usually RFCOMM channel 15)
3. Sends GAIA frames for ANC (`0x1A04`), transparency (`0x1804`), and EQ (`0x1001`)

Protocol research builds on community reverse-engineering of the Smart Control app. See [Oein/sennheiser-desktop-client](https://github.com/Oein/sennheiser-desktop-client) for the full analysis.

## Known limitations

- **Unofficial** — not affiliated with Sennheiser/Sonova
- Switching ANC ↔ Transparency may briefly interrupt music unless **Keep music playing** is enabled (disables the headphone's factory "Automatic Pause" setting)
- macOS only — uses `IOBluetooth`, not portable to Windows/Linux
- No firmware updates (out of scope)

## Development

```bash
swift build          # debug build
./build_app.sh release
```

Project layout:

```
Sources/Accentum/
  AccentumApp.swift      # Menu bar entry point
  SennheiserClient.swift # GAIA / RFCOMM client
  MenuContentView.swift  # UI
  BluetoothWatcher.swift # Connect/disconnect events
  GAIA.swift             # Protocol constants
```

## License

MIT — see [LICENSE](LICENSE).

## Credits

- Protocol documentation: [Oein/sennheiser-desktop-client](https://github.com/Oein/sennheiser-desktop-client)
- Inspired by [ZenControl](https://github.com/Oein/sennheiser-desktop-client) and community GAIA reverse-engineering
