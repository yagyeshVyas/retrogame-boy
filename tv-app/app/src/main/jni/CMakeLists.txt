cmake_minimum_required(VERSION 3.22.1)
project(retrolan_cores)

# Thin JNI bridge (RetroLAN-original code). Compiles as C11.
add_library(retro_bridge SHARED retro_core_jni.c)
target_compile_features(retro_bridge PRIVATE c_std_11)

# __android_log_print() lives in the NDK 'log' library — link it explicitly.
target_link_libraries(retro_bridge log)

# Libretro core .so files are external; the bridge dlopen()s them by name from jniLibs/<abi>/.
# They are NOT compiled here. Vendored cores come from their own GPL-compliant sources.
