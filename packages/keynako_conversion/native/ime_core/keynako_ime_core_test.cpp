#include "keynako_ime_core.h"

#include <cassert>

int main() {
    using keynako::ImeSession;
    assert(ImeSession::roman_to_hiragana("nihongo") == "にほんご");
    assert(ImeSession::roman_to_hiragana("kitte") == "きって");
    ImeSession session;
    session.set_user_dictionary({
        {"へんかん", "共有変換", 5},
        {"へんかん", "低い共有変換", 1},
    });
    for (const char value : std::string("henkan")) session.append_ascii(value);
    assert(session.reading() == "へんかん");
    assert(session.candidates().front().text == "共有変換");
    assert(session.candidates()[1].text == "低い共有変換");
    assert(!session.is_converting());
    assert(session.begin_conversion());
    assert(session.is_converting());
    assert(session.selected_index() == 0);
    session.select_next();
    assert(!session.selected_text().empty());
    assert(session.cancel_conversion());
    assert(!session.is_converting());
    assert(session.display_text() == "へんかん");
    assert(session.select_reading());
    assert(session.selected_text() == "へんかん");
    assert(!session.select_candidate(session.candidates().size()));
    assert(session.select_candidate(0));
    session.backspace();
    assert(session.raw_input() == "henka");
    assert(!session.is_converting());
    return 0;
}
