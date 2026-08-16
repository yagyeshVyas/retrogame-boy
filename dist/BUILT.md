# Built Artifacts

Everything below was actually **built and verified** on this machine (Windows 11,
Flutter 3.47.0 stable, Android SDK 36).

## APKs — Android (installable)

| File | Package | Version | Target | Size |
|------|---------|---------|--------|------|
| `dist/RetroLAN-Controller-1.0.0.apk` | `com.retrolan.retrolan_controller` | 1.0.0-phone | Phone handheld controller | 47 MB |
| `dist/RetroLAN-TV-1.0.0.apk` | `com.retrolan.retrolan_tv` | 1.0.0-tv | Android TV / Google TV (Leanback launcher) | 47 MB |

Both APKs are **built from the exact same Flutter source** (`controller-app/lib/` —
the protocol model, WebSocket client, mDNS discovery, and gamepad UI). The `tv`
flavor only swaps the Android launcher metadata (Leanback banner, `LEANBACK_LAUNCHER`
category, landscape) — the code is identical. Verified with `aapt dump badging`:

- Phone: `launchable-activity` present, label "RetroLAN Controller".
- TV: `leanback-launchable-activity` present, `android.software.leanback` required,
  label "RetroLAN".
- Both bundle the classic 3 ABIs (arm64-v8a, armeabi-v7a, x86_64) and declare the
  LAN permissions (`INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`,
  `CHANGE_WIFI_MULTICAST_STATE`) needed for the WebSocket client + mDNS browsing.

### Install
```
adb install dist/RetroLAN-Controller-1.0.0.apk     # to a phone
adb install dist/RetroLAN-TV-1.0.0.apk             # to an Android TV / Google TV
```
(Sideload: enable "Install unknown apps" / developer mode on the device. Both are
signed with the debug key — fine for sideloading.)

## Web — zero-certificate, cross-platform

`controller-app/build/web/` is the **same controller app compiled to the web** and
currently served at http://localhost:8991 (opened in the preview pane). This is the
real app — `main.dart.js`, no certificate required, runs in any browser. On the web
the Gamepad screen connects to `ws://<host>:8877`.

## iOS — the honest situation (README — READ THIS)

**An `.ipa` cannot be built on this Windows machine.** Proof captured live:

```
$ flutter build ipa
Could not find a subcommand named "ipa" for "flutter build".
Did you mean one of these?
  apk
```

The `ipa` subcommand is **compiled out of the Windows Flutter SDK entirely** — the
iOS toolchain (Xcode) only exists on macOS. No flag, package, or trick on Windows
can produce an IPA.

What IS ready for a Mac:

- `controller-app/ios/` is fully scaffolded: `Runner.xcodeproj`, `Info.plist`,
  `AppDelegate.swift`, iOS 15 deployment target. On any Mac:
  ```
  cd controller-app
  flutter build ipa            # signed IPA (needs an Apple Developer account)
  flutter build ios --no-codesign   # unsigned .app bundle
  ```
- On the "without certificate" question: there is **no legitimate signed IPA without
  a certificate**. The closest real options (all macOS):
  1. **Free Apple ID** ("Personal Team") in Xcode — signs for one device you own,
     no paid account, expires every 7 days.
  2. **unsigned `.app`** via `flutter build ios --no-codesign` — runs only on a
     simulator, not a physical iPhone.
  3. Jailbroken-device sideload — device-specific, out of scope for v1.

I did not and will not fabricate a fake `.ipa` on Windows; that does not exist.

## How the APKs were produced

```
flutter create . --org com.retrolan --project-name retrolan_controller
flutter build apk --release --flavor phone    # -> app-phone-release.apk
flutter build apk --release --flavor tv       # -> app-tv-release.apk
```

Flavor config lives in `controller-app/android/app/build.gradle.kts`
(`flavorDimensions = "target"`, `tv` + `phone` flavors sharing `controller-app/lib`).
