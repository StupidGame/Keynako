#include "keynako_ime_c_api.h"

#include "keynako_ime_core.h"

#include <string>
#include <utility>

namespace {

keynako::ImeSession *cast(keynako_ime_session session) {
    return static_cast<keynako::ImeSession *>(session);
}

const char *copy_result(std::string value) {
    thread_local std::string result;
    result = std::move(value);
    return result.c_str();
}

}  // namespace

extern "C" {

keynako_ime_session keynako_ime_create(void) { return new keynako::ImeSession(); }
void keynako_ime_destroy(keynako_ime_session session) { delete cast(session); }
void keynako_ime_set_mode(keynako_ime_session session, int english) {
    if (auto *value = cast(session)) value->set_mode(english ? keynako::InputMode::english : keynako::InputMode::japanese);
}
void keynako_ime_set_live_conversion(keynako_ime_session session, int enabled) {
    if (auto *value = cast(session)) value->set_live_conversion(enabled != 0);
}
void keynako_ime_append_ascii(keynako_ime_session session, int value) {
    if (auto *target = cast(session); target && value >= 0 && value <= 0x7f) target->append_ascii(static_cast<char>(value));
}
void keynako_ime_backspace(keynako_ime_session session) { if (auto *value = cast(session)) value->backspace(); }
void keynako_ime_clear(keynako_ime_session session) { if (auto *value = cast(session)) value->clear(); }
const char *keynako_ime_reading(keynako_ime_session session) { return session ? cast(session)->reading().c_str() : ""; }
const char *keynako_ime_display_text(keynako_ime_session session) { return session ? copy_result(cast(session)->display_text()) : ""; }
const char *keynako_ime_selected_text(keynako_ime_session session) { return session ? copy_result(cast(session)->selected_text()) : ""; }
size_t keynako_ime_candidate_count(keynako_ime_session session) { return session ? cast(session)->candidates().size() : 0; }
const char *keynako_ime_candidate_at(keynako_ime_session session, size_t index) {
    if (!session || index >= cast(session)->candidates().size()) return "";
    return cast(session)->candidates()[index].text.c_str();
}
size_t keynako_ime_selected_index(keynako_ime_session session) { return session ? cast(session)->selected_index() : 0; }
void keynako_ime_select_next(keynako_ime_session session) { if (auto *value = cast(session)) value->select_next(); }
void keynako_ime_select_previous(keynako_ime_session session) { if (auto *value = cast(session)) value->select_previous(); }
void keynako_ime_insert_zenzai(keynako_ime_session session, const char *utf8) {
    if (auto *value = cast(session); value && utf8) value->insert_zenzai_candidate(utf8);
}

}  // extern "C"
