#include "keynako_ime_c_api.h"

#include <cassert>
#include <cstring>

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
    keynako_ime_set_mode(session, 1);
    keynako_ime_append_ascii(session, 'k');
    assert(std::strcmp(keynako_ime_selected_text(session), "k") == 0);
    keynako_ime_destroy(session);
    return 0;
}
