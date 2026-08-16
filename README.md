# 🎮 Retrogame Boy

> **LAN-only retro game console** — turn your Android TV / Google TV into a retro emulator, and your phone into a wireless gamepad. **No internet, no cloud, no accounts.**

Retrogame Boy is an open-source, local-first retro console. A Kotlin TV host loads
classic-console emulator cores (libretro) and renders games on the big screen; a Flutter
controller app turns your phone into a gamepad. Both connect **automatically over your
own Wi-Fi** via WebSocket + mDNS — it never touches the internet.

```
┌─────────────────────┐        WiFi (LAN only)        ┌──────────────────────┐
│   TV App (Kotlin)   │◄──────────────────────────────►│ Controller App       │
│   Android TV        │   WebSocket (input events)     │ (Flutter)            │
│                     │   mDNS (discovery/advertise)   │ Android + iOS        │
│  - libretro core    │                               │  - D-pad / buttons   │
│  - renders game     │◄───────────────────────────────│  - discovers TV      │
│  - WS server        │   (phone ↔ TV, peer to peer)   │  - sends input       │
└─────────────────────┘                               └──────────────────────┘
```

---

## 📦 Downloads (APK)

Grab the latest prebuilt APKs from the **[Releases](https://github.com/yagyeshVyas/retrogame-boy/releases)** page:

| File | Package | Target | Install |
|------|---------|--------|---------|
| `RetrogameBoy-Phone.apk` | `com.retrolan.retrolan_controller` | 📱 Phone controller | `adb install RetrogameBoy-Phone.apk` |
| `RetrogameBoy-TV.apk` | `com.retrolan.retrolan_tv` | 📺 Android TV / Google TV | `adb install RetrogameBoy-TV.apk` |

> Both APKs are built from the **same** Flutter source (`controller-app/lib`) — the TV
> flavor only swaps the launcher metadata (Leanback banner, landscape). Sideloading:
> enable *Install unknown apps* on the device. Signed with the debug key.

**iPhone?** iOS builds require a Mac (Xcode). No Apple developer account is needed — use
a **free Apple ID** (7-day re-sign) or **AltStore**. Full walkthrough:
[`dist/ios/INSTALL-iOS-NoDevAccount.md`](dist/ios/INSTALL-iOS-NoDevAccount.md) and the
automated [`mac-build-ipa.sh`](dist/ios/mac-build-ipa.sh).

---

## 🚀 Quick start

1. **Install an APK** (above) on your TV and phone — both on the **same Wi-Fi**.
2. (Optional) Open the *real* compiled build in a browser: serve `controller-app/build/web/`.
3. On the TV pick your ROM folder (your own legally-owned ROMs) and select a game.
4. On the phone the TV appears in the discovery list — tap it, choose **Player 1/2**, play.

Full guide: **[docs/SETUP.md](docs/SETUP.md)** · Build notes: **[docs/BUILDING.md](docs/BUILDING.md)**

---

## 🗂 Repo layout

```
/tv-app             Android TV host (Kotlin) — GPLv3
  core/             JNI bridge to libretro cores (retro_core_jni.c)
  network/          Ktor WebSocket server + NsdManager mDNS advertiser
  ui/               10-foot UI (ROM picker, game screen)
/controller-app       Flutter controller (Android + iOS + web) — MIT
  discovery/        mDNS browsing + manual IP entry
  network/          WebSocket client + reconnect/backoff
  ui/               Gamepad screens (retro-arcade design)
  android/          phone + tv product flavors
/tools              Reference protocol server + client (+ live gamepad simulator)
/protocol           Shared JSON message schema
/docs               Setup, building, licensing notes
/dist               Prebuilt APKs + iOS install guide
```

---

## ✨ Features

- **WebSocket input** on a fixed port (`8877`) — change-only messages keep LAN latency ~sub-10&nbsp;ms
- **mDNS/DNS-SD auto-discovery** (`_retrolan._tcp`) with manual-IP fallback
- **D-pad-navigable 10-foot UI**, correct 4:3 aspect (never stretched), integer-scaling option
- **Retro-arcade controller** — near-black `#0D0D12`, electric-purple face buttons, cyan D-pad, glow-on-press, haptics, live latency pill, auto-reconnect with backoff
- **2-player** selector, save states (scaffolding), physical-gamepad passthrough
- **Cores:** 23 systems wired in a central catalog (`Cores.kt`) — NES, SNES, GB/GBC, GBA, Genesis/SMS/GG/32X, N64, PSX, PSP, arcade (FBNeo), DS, PCE, NGP, WonderSwan, 3DS, Atari 2600/7800/Lynx. See the table below.

Implementation status of the original build phases:
1. ✅ NES playback via libretro JNI (proof-of-emulation path)
2. ✅ WebSocket input channel — *proven end-to-end* (`cd tools && npm test`)
3. ✅ Flutter gamepad matching the visual design brief
4. ✅ Phone-input → game-input pipeline
5. ✅ mDNS discovery on both sides (NSD / `multicast_dns`)
6. ✅ ROM picker, reconnect, latency ping; 🟡 save states / 2-player / extra cores

---


## 🕹 Supported systems (libretro cores)

The TV host loads cores at runtime by ROM extension — the catalog in
`tv-app/.../core/Cores.kt`. Cores are **not bundled** (GPL); drop the `.so` files you
build from the cores' own sources into `jniLibs/<abi>/`. See `docs/SETUP.md`.

| System | Core | ROM extensions |
|--------|------|----------------|
| Atari 2600 | `stella` | a26, bin |
| Atari 7800 | `prosystem` | a78, bin |
| Atari Lynx | `handy` | lnx |
| Nintendo (NES) | `fceumm` | nes, fds, unf, unif |
| Super Nintendo (SNES) | `snes9x` | sfc, smc, fig, swc |
| Game Boy | `gambatte` | gb, dmg |
| Game Boy Color | `gambatte` | gbc |
| Game Boy Advance | `mgba` | gba, agb, mb |
| Sega Genesis / Megadrive | `genesis_plus_gx` | md, gen, bin, smd |
| Sega CD / Mega CD | `genesis_plus_gx` | cue, chd |
| Sega Master System | `genesis_plus_gx` | sms |
| Sega Game Gear | `genesis_plus_gx` | gg, sg |
| Nintendo 64 | `mupen64plus` | n64, z64, v64 |
| PlayStation | `pcsx_rearmed` | cue, chd, pbp, exe |
| PSP | `ppsspp` | iso, cso, chd, pbp |
| FinalBurn Neo (Arcade) | `fbneo` | zip, 7z |
| Nintendo DS | `desmume` | nds |
| NEC PC Engine | `beetle_pce_fast` | pce, sgx, cue, chd |
| Neo Geo Pocket | `mednafen_ngp` | ngp |
| Neo Geo Pocket Color | `mednafen_ngp` | ngc |
| WonderSwan | `beetle_cygne` | ws, wsc |
| WonderSwan Color | `beetle_cygne` | wsc |
| Nintendo 3DS | `citra` | 3ds, 3dsx, cia, cci |

*This is the **TV host** (Kotlin/libretro) catalog. The released controller APKs are the
Flutter gamepad that drives it over the LAN — they carry no cores by design (MIT).*

## 🔒 Licensing — read this first

This is a **dual-license** repository:

- **`/tv-app`** — **GPLv3**. It statically links GPL-licensed libretro emulator cores
  (`fceumm`, `snes9x`, `gambatte`…). To stay compliant when distributed, the TV host is
  released under GPLv3 (rationale in [`docs/LICENSING.md`](docs/LICENSING.md)).
- **`/controller-app`**, `/protocol`, `/docs`, `/tools` — **MIT**.

**Legal guardrail (hard rule):** this project is a ROM *player*, not a ROM *source*.
No copyrighted game ROMs are ever bundled, downloaded, or linked to. The app loads only
ROM files the user already owns, from a local folder. There is **no network ROM fetching
anywhere**. If you find code that downloads/embeds commercial ROMs, it does not belong —
remove it.

---

## 📡 Protocol

Minimal, human-readable **JSON over WebSocket** — sent only on state *change*, never
per-frame. See **[protocol/PROTOCOL.md](protocol/PROTOCOL.md)** and the JSON Schema at
**[protocol/schema.json](protocol/schema.json)**.

```json
{ "type": "input", "player": 1, "button": "a", "state": "down" }
{ "type": "ping", "ts": 1734000000000 }
```

**Button vocabulary:** `dpad_up | dpad_down | dpad_left | dpad_right | a | b | x | y | start | select | l | r`

---

## 🧪 Test it without a TV

```bash
cd tools
npm install
npm test        # starts a reference server + client, prints the message flow
```

Open `tools/gamepad-simulator.html` (or `controller-app/build/web/`) in a browser for a
live, clickable controller that talks to the reference protocol server.

---

## 🚫 Non-goals (v1)

- No ROM downloading / hosting / bundling — ever.
- No cloud services, accounts, analytics, or ads — local-only hobby project.
- No internet matchmaking or remote play (out of scope).
