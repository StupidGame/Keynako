#pragma once

#include <stddef.h>

#ifdef _WIN32
#define KEYNAKO_IME_EXPORT __declspec(dllexport)
#else
#define KEYNAKO_IME_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void *keynako_ime_session;

KEYNAKO_IME_EXPORT keynako_ime_session keynako_ime_create(void);
KEYNAKO_IME_EXPORT void keynako_ime_destroy(keynako_ime_session session);
KEYNAKO_IME_EXPORT void keynako_ime_set_mode(keynako_ime_session session, int english);
KEYNAKO_IME_EXPORT void keynako_ime_set_live_conversion(keynako_ime_session session, int enabled);
KEYNAKO_IME_EXPORT void keynako_ime_append_ascii(keynako_ime_session session, int value);
KEYNAKO_IME_EXPORT void keynako_ime_backspace(keynako_ime_session session);
KEYNAKO_IME_EXPORT void keynako_ime_clear(keynako_ime_session session);
KEYNAKO_IME_EXPORT int keynako_ime_begin_conversion(keynako_ime_session session);
KEYNAKO_IME_EXPORT int keynako_ime_cancel_conversion(keynako_ime_session session);
KEYNAKO_IME_EXPORT int keynako_ime_is_converting(keynako_ime_session session);
KEYNAKO_IME_EXPORT int keynako_ime_select_candidate(keynako_ime_session session, size_t index);
KEYNAKO_IME_EXPORT int keynako_ime_load_user_dictionary(keynako_ime_session session, const char *utf8_path);
KEYNAKO_IME_EXPORT int keynako_ime_set_bundled_dictionary_path(keynako_ime_session session, const char *utf8_path);
KEYNAKO_IME_EXPORT const char *keynako_ime_reading(keynako_ime_session session);
KEYNAKO_IME_EXPORT const char *keynako_ime_display_text(keynako_ime_session session);
KEYNAKO_IME_EXPORT const char *keynako_ime_selected_text(keynako_ime_session session);
KEYNAKO_IME_EXPORT size_t keynako_ime_candidate_count(keynako_ime_session session);
KEYNAKO_IME_EXPORT const char *keynako_ime_candidate_at(keynako_ime_session session, size_t index);
KEYNAKO_IME_EXPORT size_t keynako_ime_selected_index(keynako_ime_session session);
KEYNAKO_IME_EXPORT void keynako_ime_select_next(keynako_ime_session session);
KEYNAKO_IME_EXPORT void keynako_ime_select_previous(keynako_ime_session session);
KEYNAKO_IME_EXPORT void keynako_ime_insert_zenzai(keynako_ime_session session, const char *utf8);

#ifdef __cplusplus
}
#endif
