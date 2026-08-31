#include "keynako_ime_core.h"

#include <algorithm>
#include <cassert>
#include <cstdlib>

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

    const char *dictionary_path = std::getenv("KEYNAKO_TEST_AZOOKEY_DICTIONARY");
    assert(dictionary_path != nullptr);
    ImeSession bundled;
    assert(bundled.set_bundled_dictionary_path(dictionary_path));
    for (const char value : std::string("nihongo")) bundled.append_ascii(value);
    const auto has_japanese = std::any_of(
        bundled.candidates().begin(), bundled.candidates().end(),
        [](const keynako::Candidate &candidate) { return candidate.text == "日本語"; });
    assert(has_japanese);
    bundled.set_user_dictionary({
        {"にほん", "共有", 5, 1000.0f, 1285, 1285, true},
    });
    const auto has_combined_shared_entry = std::any_of(
        bundled.candidates().begin(), bundled.candidates().end(),
        [](const keynako::Candidate &candidate) { return candidate.text.rfind("共有", 0) == 0; });
    assert(has_combined_shared_entry);
    return 0;
}
