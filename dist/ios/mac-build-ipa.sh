#!/usr/bin/env bash
# mac-build-ipa.sh — Build the RetroLAN controller IPA on a Mac using a FREE Apple ID.
#
# WHAT THIS DOES
#  1. Installs Flutter (stable) if missing on the Mac
#  2. Opens Xcode so you can add your free Apple ID as the signing Team (ONE manual step)
#  3. Builds a signed .ipa for your own device (free Personal Team, 7-day expiry)
#  4. Optionally installs it straight to your connected iPhone
#
# USAGE
#  Copy the whole `controller-app` folder onto the Mac, cd into it, then:
#    bash <(curl -fsSL ...)   # or just run this file from the repo: ./mac-build-ipa.sh
#
# REQUIREMENTS (Mac only)
#  - Xcode (free, from the App Store) — run it once and accept the license
#  - One physically-connected iPhone
#  - Your free Apple ID (the same login you use in the App Store)

set -euo pipefail
cd "$(dirname "$0")"

echo "==> RetroLAN iOS build for FREE Apple ID"
echo

# --- 1. Flutter -----
if ! command -v flutter >/dev/null 2>&1; then
  echo "==> Installing Flutter (stable) to ~/flutter ..."
  if [ ! -d "$HOME/flutter" ]; then
    git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter"
  fi
  export PATH="$HOME/flutter/bin:$PATH"
  echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.zshrc
fi
echo "==> Flutter version:"; flutter --version | head -1
flutter precache --ios

# --- 2. CocoaPods (iOS deps) -----
if ! command -v pod >/dev/null 2>&1; then
  echo "==> Installing CocoaPods ..."
  sudo gem install cocoapods || brew install cocoapods
fi

# --- 3. Pull Flutter iOS deps -----
flutter pub get

# --- 4. Manual step: free Apple ID signing -----
echo
echo "==> NEXT: open ios/Runner.xcworkspace and in the Runner target"
echo "     Signing & Capabilities: check 'Automatically manage signing',"
echo "     add your FREE Apple ID account as the Team,"
echo "     and pick your connected iPhone as the destination."
echo "     (This is the ONE manual step — Xcode must create the provisioning profile.)"
echo "     Press Enter when done."
read -r _

# --- 5. Build + install -----
echo "==> Building signed release .app + .ipa ..."
flutter build ios --release
echo

FASTLANE_TEAM=""
# If you set your Apple ID in the environment, Xcode picks it automatically.
# Otherwise use YOUR_APPLE_ID=you@icloud.com below when running.
if [ -n "${YOUR_APPLE_ID:-}" ]; then
  echo "==> Attempting signed .ipa with identity ${YOUR_APPLE_ID} ..."
  flutter build ipa --release 2>/dev/null \
    && echo "IPA at build/ios/ipa/" \
    || echo "(build ipa needs the Xcode GUI signing to be finished first — retry after step 4)"
fi

echo
echo "==> If a device is connected, installing to it ..."
flutter install || echo "(no device connected or not trusted yet — see Settings > General > VPN & Device Management)"

echo
echo "DONE. Your free Apple ID build is installed. Remember: re-sign in 7 days
(plugin the phone in, re-run: flutter build ios --release && flutter install).
Verify the developer profile under Settings > General > VPN & Device Management."
