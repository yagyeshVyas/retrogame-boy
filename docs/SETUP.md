# Setup Guide

## Prerequisites

- **Android Studio** (or a plain Android SDK + JDK 17) for the TV app.
- **Flutter SDK** (stable channel) + Android toolchain for the controller.
  iOS builds additionally require **macOS with Xcode** (see BUILDING.md).
- Node.js ≥ 18 (only if you want to run the protocol reference test in `/tools`).

## 1. TV app

```bash
cd tv-app
# Android Studio: File > Open > tv-app, then Build > Make Project
#   or from a terminal with the SDK configured:
./gradlew :app:assembleDebug
```

Install `app-debug.apk` onto your Android TV / Google TV (or an AVD).

### Libretro cores

The JNI bridge expects core `.so` files under
`tv-app/app/src/main/jniLibs/<abi>/`. Startup core: `fceumm` (NES).

You are responsible for obtaining core binaries from their own GPL-compliant
sources (e.g. building from [libretro/libretro-fceumm](https://github.com/libretro/libretro-fceumm))
and placing them there. This repo does **not** vendor core binaries.

## 2. Controller app

```bash
cd controller-app
flutter create .            # generates missing platform scaffolding (android/, ios/)
flutter pub get
flutter run                 # on a connected phone (or emulator)
```

The phone must be on the **same LAN** as the TV. It auto-discovers the TV via
mDNS; if your network blocks multicast, use "Enter IP manually".

## 3. First game

1. On the TV, pick your ROM folder via the Storage Access Framework picker
   (your own legally-owned ROM files).
2. Select a ROM — emulation starts.
3. On the phone, the TV appears in the discovery list; tap it, pick
   Player 1 / Player 2.
4. Play.

## 4. Firewall note

Android TV usually permits inbound LAN connections on UDP 5353 (mDNS) and
TCP 8877 (WebSocket). If things don't pair, ensure your router isn't enabling
"AP/client isolation" (guest networks often do — use the main network).

## 5. Reference protocol test

```bash
cd tools
npm install
npm test     # starts a reference server + client, prints the message flow
```
