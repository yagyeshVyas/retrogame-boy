/* Minimal declaration surface of libretro.h (public API). The real header ships with
   the core build. Only the symbols our bridge references are declared here.
   RetroLAN-original glue header — extended with the structs/setters the bridge needs. */
#ifndef RETROLAN_LIBRETRO_MIN_H
#define RETROLAN_LIBRETRO_MIN_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#define RETRO_DEVICE_JOYPAD 1
#define RETRO_ENVIRONMENT_SET_GEOMETRY 19
#define RETRO_ENVIRONMENT_GET_LOG_INTERFACE 5
#define RETRO_ENVIRONMENT_GET_CAN_DUPE 30
#define RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY 9
#define RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY 31
#define RETRO_ENVIRONMENT_SET_PIXEL_FORMAT 10

#define RETRO_PIXEL_FORMAT_0RGB1555 0
#define RETRO_PIXEL_FORMAT_XRGB8888 1
#define RETRO_PIXEL_FORMAT_RGB565 2
enum retro_pixel_format { RETRO_PIXEL_FORMAT__0RGB1555 = 0, RETRO_PIXEL_FORMAT__XRGB8888 = 1, RETRO_PIXEL_FORMAT__RGB565 = 2 };

#define RETRO_DEVICE_ID_JOYPAD_B 0
#define RETRO_DEVICE_ID_JOYPAD_Y 1
#define RETRO_DEVICE_ID_JOYPAD_SELECT 2
#define RETRO_DEVICE_ID_JOYPAD_START 3
#define RETRO_DEVICE_ID_JOYPAD_UP 4
#define RETRO_DEVICE_ID_JOYPAD_DOWN 5
#define RETRO_DEVICE_ID_JOYPAD_LEFT 6
#define RETRO_DEVICE_ID_JOYPAD_RIGHT 7
#define RETRO_DEVICE_ID_JOYPAD_A 8
#define RETRO_DEVICE_ID_JOYPAD_X 9
#define RETRO_DEVICE_ID_JOYPAD_L 10
#define RETRO_DEVICE_ID_JOYPAD_R 11

struct retro_game_info {
    const char *path;
    const void *data;
    size_t size;
    const char *meta;
};

typedef bool (*retro_environment_t)(unsigned cmd, void *data);
typedef void (*retro_video_refresh_t)(const void *data, unsigned width, unsigned height, size_t pitch);
typedef void (*retro_audio_sample_t)(int16_t left, int16_t right);
typedef size_t (*retro_audio_sample_batch_t)(const int16_t *data, size_t frames);
typedef void (*retro_input_poll_t)(void);
typedef int16_t (*retro_input_state_t)(unsigned port, unsigned device, unsigned index, unsigned id);

/* Core setter entry points (what retro_set_* symbols in the .so resolve to). */
typedef void (*retro_set_environment_fn)(retro_environment_t);
typedef void (*retro_set_video_refresh_fn)(retro_video_refresh_t);
typedef void (*retro_set_audio_sample_fn)(retro_audio_sample_t);
typedef void (*retro_set_audio_sample_batch_fn)(retro_audio_sample_batch_t);
typedef void (*retro_set_input_poll_fn)(retro_input_poll_t);
typedef void (*retro_set_input_state_fn)(retro_input_state_t);

struct retro_log_callback { void (*log)(enum retro_log_level level, const char *fmt, ...); };
enum retro_log_level { RETRO_LOG_DEBUG=0, RETRO_LOG_INFO, RETRO_LOG_WARN, RETRO_LOG_ERROR };
#endif
