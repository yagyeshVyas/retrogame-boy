cmake_minimum_required(VERSION 3.22.1)
project(retrolan_cores)

# Thin JNI bridge (RetroLAN-original code).
add_library(retro_bridge SHARED retro_core_jni.c)

# Libretro core .so files are external; the bridge dlopen()s them by name from jniLibs/<abi>/.
# They are NOT compiled here. Vendored cores come from their own GPL-compliant sources.
