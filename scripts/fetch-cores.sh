#!/usr/bin/env bash
# fetch-cores.sh — Download libretro core .so binaries for the Android TV host.
#
# Sources: buildbot.libretro.com (the libretro project's canonical prebuilt core
# distribution). Cores are GPL-licensed binaries distributed by their authors;
# this repo does NOT commit them. Run this to populate jniLibs/<abi>/ before
# building the tv-app. Example:  bash scripts/fetch-cores.sh arm64-v8a
set -euo pipefail
ABI="${1:-arm64-v8a}"
DIR="tv-app/app/src/main/jniLibs/$ABI"
mkdir -p "$DIR"
BASE="https://buildbot.libretro.com/nightly/android/latest/$ABI"
WORK=".coretmp"; mkdir -p "$WORK"
# core_name|buildbot_basename
CORES="
fceumm|fceumm
snes9x|snes9x
gambatte|gambatte
mgba|mgba
genesis_plus_gx|genesis_plus_gx
pcsx_rearmed|pcsx_rearmed
ppsspp|ppsspp
fbneo|fbneo
desmume|desmume
stella|stella
prosystem|prosystem
handy|handy
mednafen_ngp|mednafen_ngp
beetle_pce_fast|mednafen_pce_fast
beetle_cygne|mednafen_wswan
citra|citra
mupen64plus|mupen64plus_next_gles3
"
for pair in $CORES; do
  core="${pair%%|*}"; name="${pair##*|}"
  url="$BASE/${name}_libretro_android.so.zip"
  if curl -sS -o "$WORK/x.zip" --max-time 90 "$url" 2>/dev/null && [ -s "$WORK/x.zip" ]; then
    rm -rf "$WORK/x"; mkdir -p "$WORK/x"
    unzip -o -q "$WORK/x.zip" -d "$WORK/x" 2>/dev/null
    so=$(find "$WORK/x" -maxdepth 1 -name "*.so" | head -1)
    if [ -n "$so" ]; then cp "$so" "$DIR/libretro_${core}.so"; echo "OK  $core"; fi
  else
    echo "SKIP $core (not found)"
  fi
done
rm -rf "$WORK"
echo "Cores in $DIR:"; ls -la "$DIR"/*.so 2>/dev/null | wc -l
