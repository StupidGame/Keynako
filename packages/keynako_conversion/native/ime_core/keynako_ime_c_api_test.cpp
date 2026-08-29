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
    keynako_ime_insert_zenzai(session, "日本語です");
    assert(std::strcmp(keynako_ime_selected_text(session), "日本語です") == 0);
    keynako_ime_set_mode(session, 1);
    keynako_ime_append_ascii(session, 'k');
    assert(std::strcmp(keynako_ime_selected_text(session), "k") == 0);
    keynako_ime_destroy(session);
    return 0;
}
