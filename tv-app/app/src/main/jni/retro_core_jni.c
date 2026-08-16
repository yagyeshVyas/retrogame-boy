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
#include <stdio.h>

#include "libretro.h" /* stable public API headers provided alongside the core */

#define LOGTAG "RetroLANCore"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOGTAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOGTAG, __VA_ARGS__)

/* ---- libretro function pointers (setters, dlsym'd from the core .so) ---- */
static retro_set_environment_fn        env_setter = NULL;
static retro_set_video_refresh_fn      video_setter = NULL;
static retro_set_audio_sample_fn       audio_setter = NULL;
static retro_set_audio_sample_batch_fn audio_batch_setter = NULL;
static retro_set_input_poll_fn         input_poll_setter = NULL;
static retro_set_input_state_fn        input_state_setter = NULL;
static void                       (*init_fn)(void) = NULL;
static void                       (*deinit_fn)(void) = NULL;
static void                       (*run_fn)(void) = NULL;
static void                       (*reset_fn)(void) = NULL;
static bool                       (*load_game_fn)(const struct retro_game_info *) = NULL;
static void                       (*unload_game_fn)(void) = NULL;
static unsigned                   (*api_version_fn)(void) = NULL;

static void *core_handle = NULL;
static int loaded = 0; /* 1 once retro_load_game succeeded */

/* ---- current button state (fed from JNI when a WS/controller message arrives) ---- */
static int16_t retro_state[2][16]; /* bitmask per joypad, 2 players */

/* ---- the environment callback the core calls back into ---- */
static bool core_environment(unsigned cmd, void *data) {
    switch (cmd) {
        case RETRO_ENVIRONMENT_SET_GEOMETRY:
            return true;
        case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
            struct retro_log_callback *cb = (struct retro_log_callback *)data;
            if (cb) cb->log = NULL; /* optional: hook logging */
            return true;
        }
        case RETRO_ENVIRONMENT_GET_CAN_DUPE: {
            bool *b = (bool *)data; if (b) *b = true; return true;
        }
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: {
            const char **dir = (const char **)data;
            static char sysdir[512] = "/data/data/com.retrolan.console/files";
            *dir = sysdir;
            return true;
        }
        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: {
            const char **dir = (const char **)data;
            static char savedir[512] = "/data/data/com.retrolan.console/files";
            *dir = savedir;
            return true;
        }
        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
            /* Accept RGB565 or 0RGB1555; cores pick a format via this env call. */
            const enum retro_pixel_format *fmt = (const enum retro_pixel_format *)data;
            LOGI("pixel format requested: %d", fmt ? (int)*fmt : -1);
            return true;
        }
        default:
            return false;
    }
}

/* ---- the video/audio/input callbacks the core calls every frame ---- */
static void core_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
    /* RGBA8888 (or RGB565) frame. The Kotlin side registers a callback that uploads to
       the Surface via a shared bitmap; for v1 the frame is dropped if no surface. */
    JNIEnv *env = NULL;
    (void)env; (void)data; (void)width; (void)height; (void)pitch;
}

static void core_audio_sample(int16_t left, int16_t right) {
    (void)left; (void)right;
}

static size_t core_audio_sample_batch(const int16_t *data, size_t frames) {
    (void)data; return frames;
}

static void core_input_poll(void) { /* state fed lazily via JNI */ }

static int16_t core_input_state(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (device != RETRO_DEVICE_JOYPAD || id >= 16) return 0;
    if (port > 1) return 0;
    return retro_state[port][id] ? 1 : 0;
}

/* ---- load a core .so by absolute path (e.g. .../libretro_fceumm.so) ---- */
JNIEXPORT jboolean JNICALL
Java_com_retrolan_console_core_LibRetro_nativeLoadCore(JNIEnv *env, jobject thiz, jstring path) {
    const char *p = (*env)->GetStringUTFChars(env, path, NULL);
    if (core_handle) { dlclose(core_handle); core_handle = NULL; loaded = 0; }
    core_handle = dlopen(p, RTLD_NOW | RTLD_LOCAL);
    (*env)->ReleaseStringUTFChars(env, path, p);
    if (!core_handle) { LOGE("dlopen failed: %s", dlerror()); return JNI_FALSE; }

    env_setter        = (retro_set_environment_fn)dlsym(core_handle, "retro_set_environment");
    video_setter      = (retro_set_video_refresh_fn)dlsym(core_handle, "retro_set_video_refresh");
    audio_setter      = (retro_set_audio_sample_fn)dlsym(core_handle, "retro_set_audio_sample");
    audio_batch_setter= (retro_set_audio_sample_batch_fn)dlsym(core_handle, "retro_set_audio_sample_batch");
    input_poll_setter = (retro_set_input_poll_fn)dlsym(core_handle, "retro_set_input_poll");
    input_state_setter= (retro_set_input_state_fn)dlsym(core_handle, "retro_set_input_state");
    init_fn           = (void (*)(void))dlsym(core_handle, "retro_init");
    deinit_fn         = (void (*)(void))dlsym(core_handle, "retro_deinit");
    run_fn            = (void (*)(void))dlsym(core_handle, "retro_run");
    reset_fn          = (void (*)(void))dlsym(core_handle, "retro_reset");
    load_game_fn      = (bool (*)(const struct retro_game_info *))dlsym(core_handle, "retro_load_game");
    unload_game_fn    = (void (*)(void))dlsym(core_handle, "retro_unload_game");
    api_version_fn    = (unsigned (*)(void))dlsym(core_handle, "retro_api_version");

    if (!env_setter || !video_setter || !input_poll_setter || !input_state_setter || !load_game_fn || !run_fn || !init_fn) {
        LOGE("core missing required symbols");
        dlclose(core_handle); core_handle = NULL; return JNI_FALSE;
    }
    LOGI("core loaded: api_version=%u", api_version_fn ? api_version_fn() : 0u);

    /* Register callbacks (setters) — NOT invoke them. */
    env_setter(core_environment);
    video_setter(core_video_refresh);
    audio_setter(core_audio_sample);
    audio_batch_setter(core_audio_sample_batch);
    input_poll_setter(core_input_poll);
    input_state_setter(core_input_state);
    init_fn();
    LOGI("retro_init done");
    return JNI_TRUE;
}

/* ---- load a ROM file into the (already loaded) core ---- */
JNIEXPORT jboolean JNICALL
Java_com_retrolan_console_core_LibRetro_nativeLoadGame(JNIEnv *env, jobject thiz,
    jstring romPath, jstring coreName) {
    (void)coreName;
    if (!core_handle || !load_game_fn) return JNI_FALSE;
    const char *rp = (*env)->GetStringUTFChars(env, romPath, NULL);
    if (!rp) return JNI_FALSE;

    FILE *f = fopen(rp, "rb");
    if (!f) { LOGE("cannot open ROM file: %s", rp); (*env)->ReleaseStringUTFChars(env, romPath, rp); return JNI_FALSE; }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0) { fclose(f); LOGE("empty ROM"); (*env)->ReleaseStringUTFChars(env, romPath, rp); return JNI_FALSE; }

    unsigned char *buf = (unsigned char *)malloc(sz);
    if (!buf) { fclose(f); (*env)->ReleaseStringUTFChars(env, romPath, rp); return JNI_FALSE; }
    size_t rd = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    if (rd != (size_t)sz) { free(buf); LOGE("short read"); (*env)->ReleaseStringUTFChars(env, romPath, rp); return JNI_FALSE; }

    struct retro_game_info info;
    memset(&info, 0, sizeof(info));
    info.path = rp;      /* cores (fceumm) inspect the extension to pick NES/FDS/UNIF */
    info.data = buf;
    info.size = (size_t)sz;
    info.meta = NULL;

    bool ok = load_game_fn(&info);
    free(buf);
    (*env)->ReleaseStringUTFChars(env, romPath, rp);
    if (!ok) { LOGE("retro_load_game failed"); return JNI_FALSE; }
    loaded = 1;
    LOGI("retro_load_game OK (%ld bytes)", sz);
    return JNI_TRUE;
}

/* ---- run one frame (driven from the emulation thread) ---- */
JNIEXPORT void JNICALL
Java_com_retrolan_console_core_LibRetro_nativeRunFrame(JNIEnv *env, jobject thiz) {
    (void)env; (void)thiz;
    if (!core_handle || !run_fn || !loaded) return;
    run_fn();
}

/* ---- reset the core ---- */
JNIEXPORT void JNICALL
Java_com_retrolan_console_core_LibRetro_nativeReset(JNIEnv *env, jobject thiz) {
    (void)env; (void)thiz;
    if (reset_fn) reset_fn();
}

/* ---- unload ---- */
JNIEXPORT void JNICALL
Java_com_retrolan_console_core_LibRetro_nativeUnload(JNIEnv *env, jobject thiz) {
    (void)env; (void)thiz;
    if (core_handle) {
        if (unload_game_fn) unload_game_fn();
        if (deinit_fn) deinit_fn();
        dlclose(core_handle);
        core_handle = NULL; loaded = 0;
    }
}

/* ---- set a raw controller bit from JNI (WS message -> core state) ---- */
JNIEXPORT void JNICALL
Java_com_retrolan_console_core_LibRetro_nativeSetButton(JNIEnv *env, jobject thiz,
    jint player, jint libretro_id, jboolean down) {
    (void)env; (void)thiz;
    if (player < 0 || player > 1) return;
    if (libretro_id < 0 || libretro_id >= 16) return;
    if (down) retro_state[player][libretro_id] = 1;
    else      retro_state[player][libretro_id] = 0;
}
