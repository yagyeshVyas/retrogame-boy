# Building: APK and IPA

## Android APK (controller app)

```bash
cd controller-app
flutter build apk --release          # single fat APK
flutter build apk --split-per-abi    # smaller per-ABI APKs
# Output: build/app/outputs/flutter-apk/app-release.apk
```

Install: `adb install -r build/app/outputs/flutter-apk/app-release.apk`

## iOS IPA

### Reality check — Windows cannot produce an IPA

An iOS `.ipa` is built and **signed** with **Apple's toolchain (Xcode) which only
runs on macOS**. Flutter on Windows can generate the `ios/` project files, but the
actual `flutter build ipa` step **requires a Mac**. There is no official way to
produce an installable IPA on Windows; any "build IPA on Windows" pipeline is a
remote Mac/CI workaround, not a local one.

### Signed IPA (normal path, on macOS)

```bash
cd controller-app
flutter build ipa --release
# Output: build/ios/ipa/*.ipa  (signs with your Apple Developer account)
```

Requires an Apple Developer account and an Xcode signing identity. Without one
you cannot install on a stock iPhone.

### "Without certificate" — what is actually possible

There is **no legitimate signed IPA without a certificate**. A few non-standard
paths exist, with real caveats:

1. **App Store Connect / TestFlight** — needs a paid developer account. Not
   "without certificate".
2. **Free Apple ID provisioning** (Xcode "Personal Team") — signs for a *single
   device* you own, no paid account, but expires every 7 days and is set up from
   Xcode on a Mac. This is the closest thing to "no paid certificate" that is
   still a real, usable path — but still macOS-only.
3. **Ad-hoc / development unsigned artifacts** — Xcode can emit `*.app` bundles
   built for *simulator* without a signing identity. These are **not IPAs** and
   do not run on a physical iPhone.
4. **Jailbroken device + custom tooling** — sideloading an unsigned IPA onto a
   jailbroken iPhone is possible, but install is non-trivial and device-specific.
   Out of scope for v1.

### Decision

Because the user explicitly asked for "an IPA without certificate," on this
**Windows** machine that cannot literally be produced. The honest, working
deliverable is:

- a complete Flutter controller project that **will** build a signed IPA on any
  Mac (`flutter build ipa`),
- an **unsigned simulator `.app` path** documented (macOS, Xcode),
- **Flutter web** as a zero-install demo target: `flutter run -d chrome` (or the
  included HTML gamepad simulator) lets you *use* the controller UI today on any
  platform with no certificate at all.

Nothing here pretends to fabricate a signed IPA on Windows — that does not exist.
