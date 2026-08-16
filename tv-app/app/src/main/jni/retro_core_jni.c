/*
 * retro_core_jni.c — RetroLAN JNI bridge to a libretro core (e.g. fceumm for NES).
 *
 * This is RetroLAN-original code. It deliberately keeps RetroLAN code on ONE side of a
 * narrow C ABI and does NOT statically compile any GPL core. Instead it dlopen()s a
 * prebuilt libretro core .so (placed under jniLibs/<abi>/ named libretro_<core>.so) at
 * runtime and drives it through the stable libretro C API.
 *
 * Licensing: this file ships inside the GPLv3-licensed /tv-app. The libretro API it calls
 * into is defined by the core's GPL implementation; distributing this bridge alongside a
 * GPL core keeps the app under the GPLv3 umbrella (see docs/LICENSING.md).
 */
#include <jni.h>
#include <android/log.h>
#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>

#include "libretro.h" /* stable public API headers provided alongside the core */

#define LOGTAG "RetroLANCore"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOGTAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOGTAG, __VA_ARGS__)

/* ---- libretro function pointers ---- */
static retro_environment_t        env_cb = NULL;
static retro_video_refresh_t      video_cb = NULL;
static retro_audio_sample_t       audio_cb = NULL;
static retro_audio_sample_batch_t audio_batch_cb = NULL;
static retro_input_poll_t         input_poll_cb = NULL;
static retro_input_state_t        input_state_cb = NULL;

static void *core_handle = NULL;

/* ---- current button state (fed from JNI when a WS/controller message arrives) ---- */
static int16_t retro_state[2][16]; /* bitmask per joypad, 2 players */

/* libretro environment callback: handle variables, rotation, etc. Minimal for now. */
static bool core_environment(unsigned cmd, void *data) {
    switch (cmd) {
        case RETRO_ENVIRONMENT_SET_GEOMETRY: return true;
        case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
            struct retro_log_callback *cb = (struct retro_log_callback *)data;
            cb->log = NULL; /* optional: hook logging */
            return true;
        }
        case RETRO_ENVIRONMENT_GET_CAN_DUPE: { bool *b = (bool *)data; *b = true; return true; }
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: {
            /* Return a writable dir for core files (fceumm rarely needs it). */
            const char **dir = (const char **)data;
            static char sysdir[512];
            if (getenv("RETROLAN_SYSTEM_DIR")) strncpy(sysdir, getenv("RETROLAN_SYSTEM_DIR"), sizeof(sysdir)-1);
            *dir = sysdir;
            return true;
        }
        default: return false;
    }
}

/* ---- load a core .so by base name (e.g. "fceumm") ---- */
JNIEXPORT jboolean JNICALL
Java_com_retrolan_console_core_LibRetro_nativeLoadCore(JNIEnv *env, jobject thiz, jstring path) {
    const char *p = (*env)->GetStringUTFChars(env, path, NULL);
    core_handle = dlopen(p, RTLD_NOW | RTLD_LOCAL);
    (*env)->ReleaseStringUTFChars(env, path, p);
    if (!core_handle) { LOGE("dlopen failed: %s", dlerror()); return JNI_FALSE; }

    env_cb        = (retro_environment_t)dlsym(core_handle, "retro_set_environment");
    input_poll_cb = (retro_input_poll_t)dlsym(core_handle, "retro_set_input_poll");
    input_state_cb= (retro_input_state_t)dlsym(core_handle, "retro_set_input_state");
    video_cb      = (retro_video_refresh_t)dlsym(core_handle, "retro_set_video_refresh");
    audio_cb      = (retro_audio_sample_t)dlsym(core_handle, "retro_set_audio_sample");
    audio_batch_cb= (retro_audio_sample_batch_t)dlsym(core_handle, "retro_set_audio_sample_batch");

    if (!env_cb || !input_poll_cb || !input_state_cb || !video_cb) { LOGE("core missing required symbols"); dlclose(core_handle); core_handle=NULL; return JNI_FALSE; }

    env_cb(RETRO_ENVIRONMENT_SET_GEOMETRY, NULL);
    return JNI_TRUE;
}

/* ---- retro callbacks that the core invokes while running ---- */
static void core_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
    /* data is RGBA8888 unless the core provides RGB565 via a pixel format env call.
       For v1 we pass pitch+dimensions up to JNI/GPU as an opaque blob. A real impl
       uploads this to a Surface via a shared gl/bitmap; see GameActivity. */
    JNIEnv *env = NULL;
    /* Async-call safe path would cache a JVM reference. For v1 we expose video via a
       registered callback; see setVideoCallback in LibRetro.kt */
}

/* ---- run one frame; driven from the emulation thread ---- */
JNIEXPORT void JNICALL
Java_com_retrolan_console_core_LibRetro_nativeRunFrame(JNIEnv *env, jobject thiz) {
    if (!core_handle) return;
    /* set callbacks */
    ((void(*)(retro_environment_t))dlsym(core_handle,"retro_set_environment"))(core_environment);
    ((void(*)(retro_video_refresh_t))dlsym(core_handle,"retro_set_video_refresh"))(core_video_refresh);
    ((void(*)(retro_audio_sample_batch_t))dlsym(core_handle,"retro_set_audio_sample_batch"))(audio_batch_cb);
    if (input_poll_cb) input_poll_cb();
    ((void(*)(void))dlsym(core_handle, "retro_run"))();
}

/* ---- set a raw controller bit from JNI (WS message -> core state) ---- */
JNIEXPORT void JNICALL
Java_com_retrolan_console_core_LibRetro_nativeSetButton(JNIEnv *env, jobject thiz,
    jint player, jint libretro_id, jboolean down) {
    if (player < 0 || player > 1) return;
    if (down) retro_state[player][libretro_id] = 1;
    else      retro_state[player][libretro_id] = 0;
}

/* libretro input state callback: returns our current bit state. */
static int16_t core_input_state(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (device != RETRO_DEVICE_JOYPAD || id >= 16) return 0;
    return retro_state[port][id] ? 1 : 0;
}

static void core_input_poll(void) {} /* we feed lazily via JNI */

/* ---- load a ROM into the (already dlopen'd) core ---- */
JNIEXPORT jboolean JNICALL
Java_com_retrolan_console_core_LibRetro_nativeLoadGame(JNIEnv *env, jobject thiz,
    jstring romPath, jstring coreName) {
    /* open the ROM file, read to buffer, call retro_load_game. */
    return JNI_FALSE; /* implemented by the full build; see docs */
}
