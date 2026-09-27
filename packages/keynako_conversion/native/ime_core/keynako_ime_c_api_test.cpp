#include "keynako_ime_c_api.h"

#include <cassert>
#include <chrono>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>

int main() {
    const auto session = keynako_ime_create();
    assert(session != nullptr);
    for (const char value : "nihongo") {
        if (value != '\0') keynako_ime_append_ascii(session, value);
    }
    assert(std::strcmp(keynako_ime_reading(session), "にほんご") == 0);
    assert(std::strcmp(keynako_ime_candidate_at(session, 0), "日本語") == 0);
    assert(keynako_ime_is_converting(session) == 0);
    assert(keynako_ime_begin_conversion(session) == 1);
    assert(keynako_ime_is_converting(session) == 1);
    assert(keynako_ime_cancel_conversion(session) == 1);
    keynako_ime_backspace(session);
    assert(std::strcmp(keynako_ime_raw_input(session), "nihong") == 0);
    keynako_ime_backspace_word(session);
    assert(std::strcmp(keynako_ime_raw_input(session), "") == 0);
    for (const char value : "nihongo") {
        if (value != '\0') keynako_ime_append_ascii(session, value);
    }
    keynako_ime_insert_zenzai(session, "日本語です");
    assert(std::strcmp(keynako_ime_selected_text(session), "日本語です") == 0);
    keynako_ime_learn_selected(session);
    keynako_ime_clear(session);
    for (const char value : "nihongo") {
        if (value != '\0') keynako_ime_append_ascii(session, value);
    }
    assert(std::strcmp(keynako_ime_selected_text(session), "日本語です") == 0);
    keynako_ime_insert_zenzai(session, "日本語");
    assert(std::strcmp(keynako_ime_selected_text(session), "日本語です") == 0);
    keynako_ime_set_mode(session, 1);
    assert(std::strcmp(keynako_ime_raw_input(session), "nihongo") == 0);
    assert(std::strcmp(keynako_ime_selected_text(session), "nihongo") == 0);
    keynako_ime_clear(session);
    keynako_ime_append_ascii(session, 'k');
    assert(std::strcmp(keynako_ime_selected_text(session), "k") == 0);

    const auto cache = std::filesystem::temp_directory_path() /
        ("keynako_empty_dictionary_" + std::to_string(
            std::chrono::steady_clock::now().time_since_epoch().count()) + ".tsv");
    {
        std::ofstream output(cache);
        output << "# keynako-shared-dictionary-v1\trevision\t1\ttoday\n"
                  "5\tかきくけこ\t独自語\n";
    }
    keynako_ime_clear(session);
    keynako_ime_set_mode(session, 0);
    for (const char value : "kakikukeko") {
        if (value != '\0') keynako_ime_append_ascii(session, value);
    }
    assert(keynako_ime_load_user_dictionary(session, cache.u8string().c_str()) == 1);
    auto has_custom_candidate = [&] {
        for (std::size_t index = 0; index < keynako_ime_candidate_count(session); ++index) {
            if (std::strcmp(keynako_ime_candidate_at(session, index), "独自語") == 0) return true;
        }
        return false;
    };
    assert(has_custom_candidate());
    {
        std::ofstream output(cache, std::ios::trunc);
        output << "# keynako-shared-dictionary-v1\tpartial\n";
    }
    assert(keynako_ime_load_user_dictionary(session, cache.u8string().c_str()) == 0);
    assert(has_custom_candidate());
    {
        std::ofstream output(cache, std::ios::trunc);
        output << "# keynako-shared-dictionary-v1\tdisabled\t1\ttoday\n";
    }
    assert(keynako_ime_load_user_dictionary(session, cache.u8string().c_str()) == 1);
    assert(!has_custom_candidate());
    std::filesystem::remove(cache);
    keynako_ime_destroy(session);
    return 0;
}
