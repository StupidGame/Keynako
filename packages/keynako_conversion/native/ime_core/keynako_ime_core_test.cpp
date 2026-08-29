#include "keynako_ime_core.h"

#include <cassert>

int main() {
    using keynako::ImeSession;
    assert(ImeSession::roman_to_hiragana("nihongo") == "にほんご");
    assert(ImeSession::roman_to_hiragana("kitte") == "きって");
    ImeSession session;
    for (const char value : std::string("henkan")) session.append_ascii(value);
    assert(session.reading() == "へんかん");
    assert(session.candidates().front().text == "変換");
    session.select_next();
    assert(!session.selected_text().empty());
    session.backspace();
    assert(session.raw_input() == "henka");
    return 0;
}
