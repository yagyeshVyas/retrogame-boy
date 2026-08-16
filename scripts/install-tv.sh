#!/bin/bash
# install-tv.sh — Install RetrogameBoy TV Emulator on a real Android TV / Google TV / ONN box.
# Usage:  bash install-tv.sh           (prompts for TV IP, uses adb wireless)
#         bash install-tv.sh 192.168.1.50   (or pass the TV's IP directly)
#
# Prereqs:
#  - adb on your PC (this machine has it).
#  - TV and PC on the SAME Wi-Fi.
#  - On the TV: Settings > About > tap "Build" 7 times to enable Developer mode,
#    then Settings > System > Developer options > enable "USB debugging" / "Wireless debugging".
set -euo pipefail

UNIVERSAL="${1:-}"
TVIP="${2:-}"
[ -z "$UNIVERSAL" ] && UNIVERSAL="$(cd "$(dirname "$0")/.." && pwd)/dist/RetrogameBoy-TV-Emulator-UNIVERSAL-1.0.0.apk"
[ -z "$TVIP" ] && { read -rp "Enter your TV's IP (Settings > Network): " TVIP; }

echo "==> Connecting to TV at $TVIP (adb wireless)..."
adb connect "$TVIP:5555" || { echo "connect failed — is Wireless debugging on?"; exit 1; }
sleep 2
echo "==> Installing universal TV APK (works on ANY Android TV / Google TV / ONN)..."
adb -s "$TVIP:5555" install -r "$UNIVERSAL" && echo "INSTALLED ✓"
echo "==> Launching RetroLAN..."
adb -s "$TVIP:5555" shell am start -n com.retrolan.console/.ui.MainActivity
echo "DONE — open the app on your TV, pick your ROM folder, play."
