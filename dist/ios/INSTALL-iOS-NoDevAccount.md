# Installing RetroLAN Controller on iPhone — the "no developer account" routes

THIS IS THE HONEST, COMPLETE GUIDE. There is NO way to install iOS software on a
real (non-jailbroken) iPhone without *some* Apple identity signing the binary —
iOS requires a code signature on every app by design. But you DO NOT need a paid
$99/yr developer account. Both routes below use a **free Apple ID**.

The hard wall you cannot escape: **none of this runs on Windows.** iOS builds
require macOS (Xcode). On this Windows machine the iOS toolchain does not exist
(`flutter build` here only offers apk/appbundle/web/windows — verified). So:
pick a Mac, then follow A below. If you have NO Mac at all, follow B (AltStore),
which still needs a Mac or Windows once to install AltStore onto the phone.

-----------------------------------------------------------------------
## ROUTE A — Real Mac, free Apple ID (Personal Team). WORKS. 7-day expiry.
-----------------------------------------------------------------------

Requires: a Mac with Xcode installed (free from the App Store), your free
Apple ID, and ONE iPhone that you own physically.

On the Mac:

```bash
# 1. Copy the whole controller-app folder to the Mac, then:
cd controller-app

# 2. Install Flutter on the Mac if not present:
git clone --depth 1 -b stable https://github.com/flutter/flutter.git ~/flutter
export PATH="$HOME/flutter/bin:$PATH"
flutter precache --ios

# 3. Open the iOS project in Xcode ONCE (it needs to create team signing):
open ios/Runner.xcworkspace
```

In Xcode, in the Runner target → **Signing & Capabilities**:
- Check the box "Automatically manage signing"
- Leave "Team" empty first, then choose "Add an Account..." and sign in with
  your FREE Apple ID (not a paid one).
- Select your free Apple ID as the Team.
- Set Bundle Identifier to something unique, e.g. `com.retrolan.controller.yourname`.

Then build and install to YOUR phone (plug it in, it auto-provisions):

```bash
flutter build ios --release         # build a signed .app for your device
flutter install                     # installs to the connected iPhone
```

If you specifically want an `.ipa` file to keep/share:
`flutter build ipa --release` produces `build/ios/ipa/*.ipa` (signed with your
free identity, for the devices on that profile).

⚠️ **The catch:** the free Personal Team certificate expires and the profile is
bound to your one device. Every **7 days** you must re-run the build/install and
re-tap Trust in Settings → General → VPN & Device Management. This is Apple's
rule for the free tier — no way around it legally.

-----------------------------------------------------------------------
## ROUTE B — No Mac at all: AltStore (free Apple ID). WORKS, still 7-day re-sign.
-----------------------------------------------------------------------

AltStore sideloads apps onto a real iPhone using your free Apple ID — no
jailbreak, no paid account. It needs a computer (Mac OR Windows) only to install
AltStore itself once; after that the phone self-manages re-signing.

### Step 1 — Install AltStore (one time, needs a PC/Mac)
1. On the iPhone, download the iOS app you want to sideload... no wait, first
   install AltStore itself:
   - Go to https://altstore.io on the computer. Download AltStore for Windows or
     Mac.
   - Install AltServer on the computer.
   - Install **iTunes + iCloud** on Windows (AltServer needs them for Apple's
     driver components). On Mac, install Xcode's command line tools.
   - Connect the iPhone via USB, run AltServer, click the AltServer tray icon →
     "Install AltStore" → your iPhone.
   - Tap Trust on the phone when prompted; verify the developer profile in
     Settings → General → VPN & Device Management.

### Step 2 — Get RetroLAN on the phone
Because you don't have a paid account, you sign and install **one app at a time**
through AltStore using your free Apple ID:

1. You need the RetroLAN **.ipa**. Since an .ipa can only be built on a Mac, if
   you have ANY Mac access, build it (Route A) and AirDrop it to the computer.
   If you have no Mac at all, a prebuilt IPA cannot be produced on this Windows
   box — this is the hard wall.
2. In AltStore on the phone: **My Apps → "+"** → pick `RetroLAN.ipa`.
   AltStore signs it with your free Apple ID and installs it.

### Step 3 — Day-to-day
AltStore (free version) auto-renews the 7-day signature **while the phone and
AltStore are on the same Wi-Fi and AltServer is running on the computer.** Open
AltStore on the phone occasionally and let it refresh; otherwise re-tap the app
in AltStore → Refresh when it's about to expire.

-----------------------------------------------------------------------
## What is NOT possible (so you don't get scammed by a tool that claims it)
-----------------------------------------------------------------------
- ❌ A signed .ipa that installs on a real iPhone with NO Apple identity at all.
- ❌ Building ANY iOS artifact on pure Windows — the toolchain does not exist here.
- ❌ An "enterprise"/"unregistered" bypass on iOS the way Android allows unsigned
  sideloads — iOS's security model forbids it.

Anything below these lines is a scam or malware vector; there is no legal trick.
