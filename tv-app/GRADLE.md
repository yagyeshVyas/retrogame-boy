# Building the TV app

## Prerequisites

- JDK 17 (installed)
- Android SDK (this machine has it at C:\Users\yagyesh\AppData\Local\Android\Sdk)
- Android Studio recommended

## Gradle

A Gradle **wrapper** (`gradlew`) is normally committed so builds don't need a local
Gradle install. To generate the wrapper (one-time, from any machine with Gradle or
by opening in Android Studio which auto-generates it):

```bash
gradle wrapper --gradle-version 8.7
```

or simply open `tv-app/` in Android Studio ("Sync" regenerates the wrapper).

## Build

```bash
cd tv-app
./gradlew :app:assembleDebug
# APK: app/build/outputs/apk/debug/app-debug.apk
```

## Libretro cores

Place core binaries named `libretro_fceumm.so`, `libretro_snes9x.so`,
`libretro_gambatte.so` under `app/src/main/jniLibs/<abi>/` (arm64-v8a, armeabi-v7a,
x86_64). These come from the cores' own GPL-compliant sources — the repo does not
vendor them.

## Layout

```
app/src/main/java/com/retrolan/console/
  core/        JNI bridge to libretro (LibRetro.kt) + retro_core_jni.c
  network/     Ktor WebSocket server + NsdManager mDNS advertiser
  ui/          MainActivity (ROM library), GameActivity (render), RomAdapter
app/src/main/jni/   CMakeLists.txt, retro_core_jni.c, libretro.h
app/src/main/jniLibs/  (vendor cores here per ABI)
```
