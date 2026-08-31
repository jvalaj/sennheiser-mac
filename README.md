# sennheiser-mac

Menu bar app for Sennheiser Accentum headphones on macOS.

Control noise cancellation, transparency, volume, and battery from your menu bar. No Dock icon — it lives in the menu bar only.

---

## Install with an AI agent

Paste this into Cursor, Claude Code, Codex, or any coding agent with terminal access:

```
Install and run the Accentum macOS menu bar app for Sennheiser headphones.

1. Clone https://github.com/jvalaj/sennheiser-mac
2. cd into the repo
3. Run: chmod +x build_app.sh && ./build_app.sh release
4. Copy Accentum.app to /Applications/
5. Launch it: open /Applications/Accentum.app
6. Tell me when macOS asks for Bluetooth permission — I need to click Allow
7. Confirm the headphones icon appears in my menu bar

Headphones must already be paired in System Settings → Bluetooth.
```

---

## Install manually

```bash
git clone https://github.com/jvalaj/sennheiser-mac.git
cd sennheiser-mac
chmod +x build_app.sh
./build_app.sh release
cp -R Accentum.app /Applications/
open /Applications/Accentum.app
```

Pair your headphones in **System Settings → Bluetooth** first. Allow **Bluetooth** when macOS asks on first launch.

---

## What it does

- Noise control — Transparency, Noise Cancellation, Off
- Volume slider
- Battery and codec info
- Auto-connect when your headphones pair

Tested on **Accentum Wireless**. May work on other recent Sennheiser models (Momentum, Accentum Plus, etc.) — open an issue if yours does not.

If connection fails, close the Sennheiser Smart Control app on your phone. It can block the control channel.

---

MIT · Unofficial — not affiliated with Sennheiser.

Protocol work builds on [Oein/sennheiser-desktop-client](https://github.com/Oein/sennheiser-desktop-client).
