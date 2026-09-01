#include "keynako_ime_core.h"

#include <algorithm>
#include <cassert>
#include <cstdlib>

int main() {
    using keynako::ImeSession;
    assert(ImeSession::roman_to_hiragana("nihongo") == "にほんご");
    assert(ImeSession::roman_to_hiragana("kitte") == "きって");
    assert(ImeSession::roman_to_hiragana("nani?") == "なに？");
    assert(ImeSession::roman_to_hiragana("nani!") == "なに！");
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

    ImeSession word_delete;
    for (const char value : std::string("hello")) word_delete.append_ascii(value);
    word_delete.backspace();
    assert(word_delete.raw_input() == "hell");
    word_delete.backspace_word();
    assert(word_delete.raw_input().empty());

    ImeSession literal_word_delete;
    for (const char value : std::string("nihongo")) literal_word_delete.append_ascii(value);
    for (const char value : std::string("OpenAI")) {
        literal_word_delete.append_literal_ascii(value);
    }
    literal_word_delete.backspace_word();
    assert(literal_word_delete.raw_input() == "nihongo");
    assert(literal_word_delete.display_text() == "日本語");

    ImeSession question_mark;
    question_mark.set_user_dictionary({
        {"なに", "何", 5},
    });
    for (const char value : std::string("nani")) question_mark.append_ascii(value);
    assert(question_mark.display_text() == "何");
    question_mark.insert_zenzai_candidate("何なの");
    assert(question_mark.begin_conversion());
    question_mark.append_ascii('?');
    assert(question_mark.raw_input() == "nani?");
    assert(question_mark.reading() == "なに？");
    assert(question_mark.display_text() == "何なの？");
    assert(question_mark.is_converting());
    question_mark.append_ascii('!');
    assert(question_mark.reading() == "なに？！");
    assert(question_mark.display_text() == "何なの？！");
    question_mark.backspace();
    assert(question_mark.display_text() == "何なの？");

    ImeSession english_punctuation;
    english_punctuation.set_mode(keynako::InputMode::english);
    english_punctuation.append_ascii('!');
    english_punctuation.append_ascii('?');
    assert(english_punctuation.reading() == "!?");
    assert(english_punctuation.display_text() == "!?");

    ImeSession mixed_text;
    mixed_text.set_user_dictionary({
        {"にほんご", "日本語", 5},
    });
    for (const char value : std::string("nihongo")) mixed_text.append_ascii(value);
    assert(mixed_text.display_text() == "日本語");
    mixed_text.insert_zenzai_candidate("日本語入力");
    assert(mixed_text.begin_conversion());
    for (const char value : std::string("OpenAI")) {
        mixed_text.append_literal_ascii(value);
    }
    assert(mixed_text.raw_input() == "nihongoOpenAI");
    assert(mixed_text.reading() == "にほんごOpenAI");
    assert(mixed_text.display_text() == "日本語入力OpenAI");
    assert(mixed_text.has_literal_suffix());
    mixed_text.append_ascii('?');
    assert(mixed_text.display_text() == "日本語入力OpenAI？");
    mixed_text.backspace();
    assert(mixed_text.display_text() == "日本語入力OpenAI");

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
