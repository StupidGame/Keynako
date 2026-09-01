#include "keynako_ime_c_api.h"

#include "keynako_ime_core.h"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <string>
#include <utility>
#include <vector>

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
int keynako_ime_begin_conversion(keynako_ime_session session) {
    return session && cast(session)->begin_conversion() ? 1 : 0;
}
int keynako_ime_cancel_conversion(keynako_ime_session session) {
    return session && cast(session)->cancel_conversion() ? 1 : 0;
}
int keynako_ime_is_converting(keynako_ime_session session) {
    return session && cast(session)->is_converting() ? 1 : 0;
}
int keynako_ime_select_candidate(keynako_ime_session session, size_t index) {
    return session && cast(session)->select_candidate(index) ? 1 : 0;
}
int keynako_ime_load_user_dictionary(keynako_ime_session session, const char *utf8_path) {
    if (!session || !utf8_path || !*utf8_path) return 0;
    std::ifstream stream(std::filesystem::u8path(utf8_path), std::ios::binary);
    if (!stream) return 0;
    std::vector<keynako::DictionaryEntry> entries;
    std::string line;
    bool valid_header = false;
    while (std::getline(stream, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.rfind("# keynako-shared-dictionary-v1", 0) == 0) {
            valid_header = true;
            continue;
        }
        if (line.empty() || line.front() == '#') continue;
        const auto first_tab = line.find('\t');
        const auto second_tab = first_tab == std::string::npos
            ? std::string::npos
            : line.find('\t', first_tab + 1);
        if (first_tab == std::string::npos || second_tab == std::string::npos) continue;
        try {
            const int importance = std::clamp(std::stoi(line.substr(0, first_tab)), 1, 5);
            std::string reading = line.substr(first_tab + 1, second_tab - first_tab - 1);
            const auto third_tab = line.find('\t', second_tab + 1);
            std::string value = third_tab == std::string::npos
                ? line.substr(second_tab + 1)
                : line.substr(second_tab + 1, third_tab - second_tab - 1);
            if (!reading.empty() && !value.empty()) {
                keynako::DictionaryEntry entry{std::move(reading), std::move(value), importance};
                if (third_tab != std::string::npos) {
                    const auto fourth_tab = line.find('\t', third_tab + 1);
                    const auto fifth_tab = fourth_tab == std::string::npos
                        ? std::string::npos
                        : line.find('\t', fourth_tab + 1);
                    if (fourth_tab != std::string::npos && fifth_tab != std::string::npos) {
                        entry.word_weight = std::stof(line.substr(third_tab + 1, fourth_tab - third_tab - 1));
                        entry.lcid = std::stoi(line.substr(fourth_tab + 1, fifth_tab - fourth_tab - 1));
                        entry.rcid = std::stoi(line.substr(fifth_tab + 1));
                        entry.has_word_weight = true;
                    }
                }
                entries.push_back(std::move(entry));
            }
        } catch (const std::exception &) {
            continue;
        }
    }
    if (!valid_header || entries.empty()) return 0;
    cast(session)->set_user_dictionary(std::move(entries));
    return 1;
}
int keynako_ime_set_bundled_dictionary_path(keynako_ime_session session, const char *utf8_path) {
    return session && utf8_path && cast(session)->set_bundled_dictionary_path(utf8_path) ? 1 : 0;
}
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
