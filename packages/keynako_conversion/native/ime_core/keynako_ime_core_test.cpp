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
    ImeSession learning;
    for (int repeat = 0; repeat < 100; ++repeat) {
        for (const char value : std::string("ai")) learning.append_ascii(value);
        assert(learning.begin_conversion());
        const auto preferred = std::find_if(learning.candidates().begin(), learning.candidates().end(),
            [](const auto &candidate) { return candidate.text == "愛"; });
        assert(preferred != learning.candidates().end());
        assert(learning.select_candidate(static_cast<std::size_t>(preferred - learning.candidates().begin())));
        assert(learning.selected_text() == "愛");
        learning.learn_selected();
        learning.clear();
    }
    for (const char value : std::string("ai")) learning.append_ascii(value);
    assert(learning.begin_conversion());
    const auto indigo = std::find_if(learning.candidates().begin(), learning.candidates().end(),
        [](const auto &candidate) { return candidate.text == "藍"; });
    assert(indigo != learning.candidates().end());
    assert(learning.select_candidate(static_cast<std::size_t>(indigo - learning.candidates().begin())));
    learning.insert_zenzai_candidate("愛");
    assert(learning.selected_text() == "藍");
    learning.learn_selected();
    learning.clear();
    for (const char value : std::string("ai")) learning.append_ascii(value);
    assert(std::any_of(learning.candidates().begin(), learning.candidates().end(),
        [](const auto &candidate) { return candidate.text == "藍"; }));
    learning.insert_zenzai_candidate("愛");
    assert(learning.selected_text() == "愛");

    // A learned unconverted reading must still support the reading shortcut.
    assert(learning.select_reading());
    assert(learning.selected_text() == "あい");
    learning.learn_selected();
    learning.clear();
    for (const char value : std::string("ai")) learning.append_ascii(value);
    assert(learning.select_reading());
    assert(learning.selected_text() == "あい");

    ImeSession recalled;
    for (const char value : std::string("kiinako")) recalled.append_ascii(value);
    recalled.insert_zenzai_candidate("Keynako");
    recalled.learn_selected();
    recalled.clear();
    for (const char value : std::string("kiinako")) recalled.append_ascii(value);
    assert(std::any_of(recalled.candidates().begin(), recalled.candidates().end(),
        [](const auto &candidate) { return candidate.text == "Keynako"; }));
    recalled.clear();
    for (const char value : std::string("kii")) recalled.append_ascii(value);
    assert(recalled.display_text() == "きい");
    assert(std::any_of(recalled.candidates().begin(), recalled.candidates().end(),
        [](const auto &candidate) { return candidate.text == "Keynako"; }));

    ImeSession fixed_priority;
    for (const char value : std::string("tesuto")) fixed_priority.append_ascii(value);
    fixed_priority.insert_zenzai_candidate("学習語");
    const auto learned_model = std::find_if(fixed_priority.candidates().begin(), fixed_priority.candidates().end(),
        [](const auto &candidate) { return candidate.text == "学習語"; });
    assert(learned_model != fixed_priority.candidates().end());
    assert(fixed_priority.begin_conversion());
    assert(fixed_priority.select_candidate(static_cast<std::size_t>(learned_model - fixed_priority.candidates().begin())));
    fixed_priority.learn_selected();
    fixed_priority.clear();
    fixed_priority.set_user_dictionary({{"てすと", "登録語", 3}});
    for (const char value : std::string("tesuto")) fixed_priority.append_ascii(value);
    assert(fixed_priority.candidates()[0].text == "登録語");
    assert(fixed_priority.candidates()[1].text == "学習語");
    fixed_priority.insert_zenzai_candidate("一致モデル");
    assert(fixed_priority.candidates()[0].text == "一致モデル");
    assert(fixed_priority.candidates()[1].text == "登録語");
    assert(fixed_priority.candidates()[2].text == "学習語");
    fixed_priority.clear();
    for (const char value : std::string("tesu")) fixed_priority.append_ascii(value);
    assert(fixed_priority.candidates()[0].text == "登録語");
    assert(fixed_priority.candidates()[0].source == "shared-prediction");
    assert(fixed_priority.candidates()[1].text == "学習語");
    assert(fixed_priority.display_text() == "てす");
    fixed_priority.insert_zenzai_candidate("一致モデル");
    assert(fixed_priority.candidates()[0].text == "一致モデル");
    assert(fixed_priority.candidates()[1].text == "登録語");
    assert(fixed_priority.candidates()[2].text == "学習語");

    ImeSession session;
    session.set_user_dictionary({
        {"へんかん", "共有変換", 5},
        {"へんかん", "低い共有変換", 1},
    });
    for (const char value : std::string("henkan")) session.append_ascii(value);
    assert(session.reading() == "へんかん");
    assert(session.candidates().front().text == "変換");
    assert(session.candidates()[1].text == "共有変換");
    assert(session.candidates()[2].text == "低い共有変換");
    assert(!session.is_converting());

    ImeSession prefix_prediction;
    prefix_prediction.set_user_dictionary({
        {"にほん", "日本", 5},
        {"にほんご", "日本語入力", 4},
    });
    for (const char value : std::string("niho")) prefix_prediction.append_ascii(value);
    assert(prefix_prediction.display_text() == "にほ");
    assert(prefix_prediction.candidates().size() >= 4);
    assert(prefix_prediction.candidates().front().source == "dictionary-prediction");
    assert(prefix_prediction.candidates()[2].text == "日本");
    assert(prefix_prediction.candidates()[2].source == "shared-prediction");
    ImeSession rider_prediction;
    rider_prediction.set_user_dictionary({{"かめんらいだー", "仮面ライダー", 3}});
    for (const auto &raw : {"kame", "kamen"}) {
        rider_prediction.clear();
        for (const char value : std::string(raw)) rider_prediction.append_ascii(value);
        const auto &values = rider_prediction.candidates();
        const auto found = std::find_if(values.begin(), values.end(), [](const auto &candidate) {
            return candidate.text == "仮面ライダー" &&
                candidate.source.find("prediction") != std::string::npos;
        });
        assert(found != values.end());
        assert(found - values.begin() < 3);
        assert(rider_prediction.candidate_reading(static_cast<std::size_t>(found - values.begin())) ==
            "かめんらいだー");
        assert(rider_prediction.display_text() != "仮面ライダー");
        assert(rider_prediction.begin_conversion());
        assert(rider_prediction.select_candidate(static_cast<std::size_t>(found - values.begin())));
        rider_prediction.learn_selected();
        rider_prediction.cancel_conversion();
        rider_prediction.clear();
        for (const char value : std::string(raw)) rider_prediction.append_ascii(value);
        assert(rider_prediction.candidates().front().text == "仮面ライダー");
        assert(rider_prediction.display_text() != "仮面ライダー");
    }
    ImeSession learned_rider;
    for (const char value : std::string("kamenraida-")) learned_rider.append_ascii(value);
    learned_rider.insert_zenzai_candidate("仮面ライダー");
    assert(learned_rider.selected_text() == "仮面ライダー");
    learned_rider.learn_selected();
    for (const auto &raw : {"kame", "kamen"}) {
        learned_rider.clear();
        for (const char value : std::string(raw)) learned_rider.append_ascii(value);
        assert(learned_rider.candidates().front().text == "仮面ライダー");
        assert(learned_rider.candidates().size() > 1);
        assert(learned_rider.candidates().front().source == "learned-prediction");
        assert(learned_rider.candidate_reading(0) == "かめんらいだー");
        assert(learned_rider.display_text() != "仮面ライダー");
        learned_rider.insert_zenzai_candidate("仮面ライダー");
        assert(learned_rider.candidates().front().source == "learned-prediction");
        assert(learned_rider.display_text() != "仮面ライダー");
        assert(learned_rider.begin_conversion());
        assert(learned_rider.select_candidate(0));
        learned_rider.learn_selected();
    }
    keynako::DictionaryEntry personal_entry{"てすと", "個人語", 5};
    personal_entry.source = "personal";
    ImeSession personal_dictionary;
    personal_dictionary.set_user_dictionary({personal_entry});
    for (const char value : std::string("tesuto")) personal_dictionary.append_ascii(value);
    assert(personal_dictionary.candidates().front().source == "personal");
    personal_dictionary.clear();
    for (const char value : std::string("tesu")) personal_dictionary.append_ascii(value);
    assert(std::any_of(personal_dictionary.candidates().begin(), personal_dictionary.candidates().end(),
        [](const auto &candidate) { return candidate.text == "個人語" &&
            candidate.source == "personal-prediction"; }));
    ImeSession combined_dictionary;
    keynako::DictionaryEntry shared_name{"れいな", "レイナ", 3};
    shared_name.source = "shared";
    keynako::DictionaryEntry personal_name{"まきな", "マキナ", 3};
    personal_name.source = "personal";
    combined_dictionary.set_user_dictionary({shared_name, personal_name});
    for (const char value : std::string("makinatoreina")) combined_dictionary.append_ascii(value);
    assert(std::any_of(combined_dictionary.candidates().begin(), combined_dictionary.candidates().end(),
        [](const auto &candidate) { return candidate.text == "マキナとレイナ" &&
            candidate.source == "dictionary-combination"; }));
    for (const auto &input : {"amakinatoreina", "makinapyoreina", "makinatoreinapyo"}) {
        combined_dictionary.clear();
        for (const char value : std::string(input)) combined_dictionary.append_ascii(value);
        assert(std::none_of(combined_dictionary.candidates().begin(),
            combined_dictionary.candidates().end(), [](const auto &candidate) {
                return candidate.source == "dictionary-combination";
            }));
    }
    combined_dictionary.clear();
    for (const char value : std::string("makinatoreinamo")) combined_dictionary.append_ascii(value);
    assert(std::any_of(combined_dictionary.candidates().begin(), combined_dictionary.candidates().end(),
        [](const auto &candidate) { return candidate.text == "マキナとレイナも" &&
            candidate.source == "dictionary-combination"; }));
    ImeSession mixed_dictionary;
    mixed_dictionary.set_user_dictionary({{"ねこ", "猫", 3}});
    for (const char value : std::string("watashihaneko")) mixed_dictionary.append_ascii(value);
    assert(std::any_of(mixed_dictionary.candidates().begin(), mixed_dictionary.candidates().end(),
        [](const auto &candidate) { return candidate.text == "私は猫"; }));
    ImeSession learned_combination;
    for (const auto &[ruby, word] : std::vector<std::pair<std::string, std::string>>{
             {"watashi", "私"}, {"neko", "猫"}}) {
        learned_combination.set_user_dictionary({{ImeSession::roman_to_hiragana(ruby), word, 3}});
        for (const char value : ruby) learned_combination.append_ascii(value);
        const std::string target = word;
        const auto model_word = std::find_if(learned_combination.candidates().begin(), learned_combination.candidates().end(),
            [&target](const auto &candidate) { return candidate.text == target; });
        assert(model_word != learned_combination.candidates().end());
        assert(learned_combination.begin_conversion());
        assert(learned_combination.select_candidate(static_cast<std::size_t>(model_word - learned_combination.candidates().begin())));
        assert(learned_combination.selected_text() == word);
        learned_combination.learn_selected();
        learned_combination.clear();
    }
    learned_combination.set_user_dictionary({});
    for (const char value : std::string("watashihaneko")) learned_combination.append_ascii(value);
    assert(std::any_of(learned_combination.candidates().begin(), learned_combination.candidates().end(),
        [](const auto &candidate) { return candidate.text == "私は猫" &&
            candidate.source == "learned-combination"; }));
    ImeSession special_number;
    for (const char value : std::string("1234")) special_number.append_ascii(value);
    assert(std::any_of(special_number.candidates().begin(), special_number.candidates().end(),
        [](const auto &candidate) { return candidate.text == "1,234" && candidate.source == "special"; }));
    assert(std::any_of(special_number.candidates().begin(), special_number.candidates().end(),
        [](const auto &candidate) { return candidate.text == "12:34" && candidate.source == "special"; }));
    ImeSession special_year;
    for (const char value : std::string("2019nen")) special_year.append_ascii(value);
    assert(std::any_of(special_year.candidates().begin(), special_year.candidates().end(),
        [](const auto &candidate) { return candidate.text == "令和元年" && candidate.source == "special"; }));
    ImeSession special_email;
    special_email.set_mode(keynako::InputMode::english);
    for (const char value : std::string("azooKey@g")) special_email.append_ascii(value);
    assert(std::any_of(special_email.candidates().begin(), special_email.candidates().end(),
        [](const auto &candidate) { return candidate.text == "azooKey@gmail.com" &&
            candidate.source == "email-prediction"; }));
    ImeSession ranked_prediction;
    ranked_prediction.set_user_dictionary({
        {"テストケース", "長い補完", 3},
        {"テスト", "短い補完", 3},
        {"テストヨソク", "重要な補完", 5},
    });
    for (const char value : std::string("tesu")) ranked_prediction.append_ascii(value);
    assert(ranked_prediction.display_text() == "てす");
    assert(ranked_prediction.candidates()[0].text == "重要な補完");
    assert(ranked_prediction.candidates()[1].text == "短い補完");
    ImeSession closer_prediction;
    closer_prediction.set_user_dictionary({
        {"テストケースナガイヨソク", "遠い高重要度", 5},
        {"テスト", "近い補完", 4},
    });
    for (const char value : std::string("tesu")) closer_prediction.append_ascii(value);
    assert(closer_prediction.candidates()[0].text == "近い補完");
    ranked_prediction.clear();
    ranked_prediction.append_ascii('/');
    assert(std::none_of(ranked_prediction.candidates().begin(), ranked_prediction.candidates().end(),
        [](const keynako::Candidate &candidate) { return candidate.source.find("prediction") != std::string::npos; }));
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

    ImeSession japanese_phrase_word_delete;
    for (const char value : std::string("watashihanihongowonyuuryoku")) {
        japanese_phrase_word_delete.append_ascii(value);
    }
    japanese_phrase_word_delete.backspace();
    assert(japanese_phrase_word_delete.raw_input() ==
           "watashihanihongowonyuuryok");
    japanese_phrase_word_delete.backspace_word();
    assert(japanese_phrase_word_delete.raw_input() == "watashihanihongowo");
    japanese_phrase_word_delete.backspace();
    assert(japanese_phrase_word_delete.raw_input() == "watashihanihongow");
    japanese_phrase_word_delete.backspace_word();
    assert(japanese_phrase_word_delete.raw_input() == "watashihanihongo");
    japanese_phrase_word_delete.backspace_word();
    assert(japanese_phrase_word_delete.raw_input() == "watashiha");

    ImeSession lexical_word_delete;
    for (const char value : std::string("kimono")) lexical_word_delete.append_ascii(value);
    lexical_word_delete.backspace_word();
    assert(lexical_word_delete.raw_input().empty());
    for (const char value : std::string("tamanokoshi")) lexical_word_delete.append_ascii(value);
    lexical_word_delete.backspace_word();
    assert(lexical_word_delete.raw_input().empty());

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
    const auto generated = std::find_if(question_mark.candidates().begin(), question_mark.candidates().end(),
        [](const auto &candidate) { return candidate.text == "何なの"; });
    assert(generated != question_mark.candidates().end());
    assert(question_mark.select_candidate(static_cast<std::size_t>(generated - question_mark.candidates().begin())));
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

    ImeSession mode_switch;
    for (const char value : std::string("nihongo")) mode_switch.append_ascii(value);
    assert(mode_switch.begin_conversion());
    mode_switch.set_mode(keynako::InputMode::english);
    assert(mode_switch.raw_input() == "nihongo");
    assert(mode_switch.reading() == "nihongo");
    assert(mode_switch.is_converting());
    mode_switch.set_mode(keynako::InputMode::japanese);
    assert(mode_switch.raw_input() == "nihongo");
    assert(mode_switch.reading() == "にほんご");
    assert(mode_switch.is_converting());
    assert(mode_switch.display_text() == "日本語");
    assert(std::any_of(
        mode_switch.candidates().begin(), mode_switch.candidates().end(),
        [](const keynako::Candidate &candidate) {
            return candidate.text == "日本語";
        }));

    ImeSession shifted_roman;
    shifted_roman.set_user_dictionary({
        {"にほんご", "日本語", 5},
    });
    for (const char value : std::string("niHonGo")) shifted_roman.append_ascii(value);
    assert(shifted_roman.reading() == "にほんご");
    assert(shifted_roman.display_text() == "日本語");
    assert(!shifted_roman.has_literal_suffix());

    ImeSession mixed_text;
    mixed_text.set_user_dictionary({
        {"にほんご", "日本語", 5},
    });
    for (const char value : std::string("nihongo")) mixed_text.append_ascii(value);
    assert(mixed_text.display_text() == "日本語");
    mixed_text.insert_zenzai_candidate("日本語入力");
    assert(mixed_text.begin_conversion());
    const auto mixed_generated = std::find_if(mixed_text.candidates().begin(), mixed_text.candidates().end(),
        [](const auto &candidate) { return candidate.text == "日本語入力"; });
    assert(mixed_generated != mixed_text.candidates().end());
    assert(mixed_text.select_candidate(static_cast<std::size_t>(mixed_generated - mixed_text.candidates().begin())));
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
    keynako::AzooKeyDictionary dictionary(dictionary_path);
    assert(dictionary.predictions("よろ", 1).front() == "よろしく");
    assert(dictionary.predictions("にほ", 1).front() == "日本");
    assert(dictionary.predictions("こんに", 1).front() == "こんにちは");
    const auto ordinary_conversion = dictionary.candidates("へんかん", 48);
    assert(!ordinary_conversion.empty() && ordinary_conversion.front() == "変換");
    assert(std::find(ordinary_conversion.begin(), ordinary_conversion.end(), "返翰") ==
        ordinary_conversion.end());
    const std::vector<keynako::AzooKeyAdditionalEntry> combined_entries = {
        {"マキナ", "まきな", 1285, 1285, -8.0f},
        {"レイナ", "れいな", 1285, 1285, -8.0f},
    };
    const auto exact_combination = dictionary.candidates("まきなとれいな", 48, combined_entries);
    assert(std::find(exact_combination.begin(), exact_combination.end(), "マキナとレイナ") !=
        exact_combination.end());
    ImeSession exact_combination_session;
    assert(exact_combination_session.set_bundled_dictionary_path(dictionary_path));
    exact_combination_session.set_user_dictionary({
        {"まきな", "マキナ", 3}, {"れいな", "レイナ", 3},
    });
    for (const auto &input : {"amakinatoreina", "makinapyoreina", "makinatoreinapyo"}) {
        exact_combination_session.clear();
        for (const char value : std::string(input)) exact_combination_session.append_ascii(value);
        assert(std::none_of(exact_combination_session.candidates().begin(),
            exact_combination_session.candidates().end(), [](const auto &candidate) {
            return candidate.text.find("マキナ") != std::string::npos &&
                candidate.text.find("レイナ") != std::string::npos;
        }));
    }
    exact_combination_session.insert_zenzai_candidate("マキナとレイナピョ");
    assert(std::none_of(exact_combination_session.candidates().begin(),
        exact_combination_session.candidates().end(), [](const auto &candidate) {
        return candidate.text == "マキナとレイナピョ";
    }));
    exact_combination_session.clear();
    for (const char value : std::string("makinatoreinamo")) exact_combination_session.append_ascii(value);
    assert(std::any_of(exact_combination_session.candidates().begin(),
        exact_combination_session.candidates().end(), [](const auto &candidate) {
        return candidate.text == "マキナとレイナも";
    }));
    // Same long input and leading result as azooKey's ConverterTests.swift.
    const auto reference_long_sentence = dictionary.candidates(
        "ようしょうきからてにすすいえいやきゅうしょうりんじけんぽうなどさまざまなすぽーつをけいけんしながらそだちしょうがっこうじだいはろさんぜるすきんこうにたいざいしておりごるふやてにすをならっていた", 5);
    assert(!reference_long_sentence.empty() && reference_long_sentence.front() ==
        "幼少期からテニス水泳野球少林寺拳法など様々なスポーツを経験しながら育ち小学校時代はロサンゼルス近郊に滞在しておりゴルフやテニスを習っていた");
    assert(dictionary.candidates("くろすうぉーず", 1).front() == "クロスウォーズ");
    assert(dictionary.candidates("さぷらい", 1).front() == "サプライ");
    assert(dictionary.candidates("ようこそ", 1).front() == "ようこそ");
    assert(dictionary.candidates("とかも", 1).front() == "とかも");
    assert(dictionary.candidates("ないか", 1).front() == "無いか");
    assert(dictionary.candidates("あいふぉん", 1).front() == "iPhone");
    assert(dictionary.candidates("くろす", 1,
        {{"CROSS", "くろす", 1285, 1285, 0.0f}}).front() == "CROSS");
    ImeSession negative_question;
    assert(negative_question.set_bundled_dictionary_path(dictionary_path));
    for (const char value : std::string("naika")) negative_question.append_ascii(value);
    assert(negative_question.candidates().front().text == "無いか");
    negative_question.insert_zenzai_candidate("内科");
    assert(negative_question.candidates().front().text == "無いか");
    ImeSession katakana_word;
    assert(katakana_word.set_bundled_dictionary_path(dictionary_path));
    for (const char value : std::string("sapurai")) katakana_word.append_ascii(value);
    assert(katakana_word.candidates().front().text == "サプライ");
    katakana_word.insert_zenzai_candidate("さプライ");
    assert(katakana_word.candidates().front().text == "サプライ");
    ImeSession kana_word;
    assert(kana_word.set_bundled_dictionary_path(dictionary_path));
    for (const char value : std::string("youkoso")) kana_word.append_ascii(value);
    assert(kana_word.candidates().front().text == "ようこそ");
    kana_word.insert_zenzai_candidate("葉こそ");
    assert(kana_word.candidates().front().text == "ようこそ");
    ImeSession kana_phrase;
    assert(kana_phrase.set_bundled_dictionary_path(dictionary_path));
    for (const char value : std::string("tokamo")) kana_phrase.append_ascii(value);
    assert(kana_phrase.candidates().front().text == "とかも");
    kana_phrase.insert_zenzai_candidate("渡河も");
    assert(kana_phrase.candidates().front().text == "とかも");
    ImeSession short_reading;
    assert(short_reading.set_bundled_dictionary_path(dictionary_path));
    for (const char value : std::string("te")) short_reading.append_ascii(value);
    assert(short_reading.candidates().front().text == "て");
    short_reading.insert_zenzai_candidate("て゚");
    assert(short_reading.candidates().front().text == "て");
    assert(std::none_of(short_reading.candidates().begin(), short_reading.candidates().end(),
        [](const auto &candidate) { return candidate.text == "て゚"; }));
    const auto requests = dictionary.predictions("おねが", 3);
    assert(std::find(requests.begin(), requests.end(), "お願いします") != requests.end());
    assert(std::find(requests.begin(), requests.end(), "お願いし") == requests.end());
    const auto ranked_completions = dictionary.predictions("てす", 2, {
        {"長い補完", "テストケース", 1285, 1285, 1000.0f},
        {"短い補完", "テスト", 1285, 1285, 1000.0f},
    });
    assert(ranked_completions == std::vector<std::string>({"短い補完", "長い補完"}));
    ImeSession bundled;
    assert(bundled.set_bundled_dictionary_path(dictionary_path));
    for (const char value : std::string("nihongo")) bundled.append_ascii(value);
    const auto normal_first = bundled.candidates().front().text;
    bundled.insert_zenzai_candidate("珍しい候補");
    assert(bundled.candidates().front().text == normal_first);
    ImeSession grammatical_kana;
    assert(grammatical_kana.set_bundled_dictionary_path(dictionary_path));
    for (const char value : std::string("shite")) grammatical_kana.append_ascii(value);
    assert(grammatical_kana.candidates().front().text == "して");
    grammatical_kana.insert_zenzai_candidate("仕手");
    assert(grammatical_kana.candidates().front().text == "して");
    ImeSession polite_kana;
    assert(polite_kana.set_bundled_dictionary_path(dictionary_path));
    for (const char value : std::string("masu")) polite_kana.append_ascii(value);
    assert(polite_kana.candidates().front().text == "ます");
    const auto has_japanese = std::any_of(
        bundled.candidates().begin(), bundled.candidates().end(),
        [](const keynako::Candidate &candidate) { return candidate.text == "日本語"; });
    assert(has_japanese);
    const auto long_sentence = dictionary.candidates(
        "わたしはきょうとうきょうのえきでともだちとあいました", 1);
    assert(!long_sentence.empty() &&
           long_sentence.front() == "私は今日東京の駅で友達と会いました");
    const auto registered_long_sentence = dictionary.candidates(
        "わたしはきょうとうきょうのえきでともだちとあいましたそしてあしたもとうきょうにいきます",
        48, {{"拙者", "わたし", 1285, 1285, -9.0f}});
    assert(std::any_of(registered_long_sentence.begin(), registered_long_sentence.end(),
        [](const std::string &candidate) {
            return candidate.rfind("拙者は今日東京の駅で友達と会いました", 0) == 0;
        }));
    // Appending kana must produce the same ranked paths as a fresh search,
    // including after a new registered-word mask becomes active.
    keynako::AzooKeyDictionary incremental_dictionary(dictionary_path);
    const std::vector<keynako::AzooKeyAdditionalEntry> incremental_entries = {
        {"拙者", "わたし", 1285, 1285, -9.0f},
        {"友達", "ともだち", 1285, 1285, -9.0f},
    };
    for (const auto &prefix : {"わたし", "わたしはきょう", "わたしはきょうとうきょうのえきで",
                               "わたしはきょうとうきょうのえきでともだち",
                               "わたしはきょうとうきょうのえきでともだちとあいました"}) {
        const auto incremental = incremental_dictionary.candidates(prefix, 48, incremental_entries);
        keynako::AzooKeyDictionary fresh_dictionary(dictionary_path);
        assert(incremental == fresh_dictionary.candidates(prefix, 48, incremental_entries));
    }
    ImeSession registered_long_path;
    assert(registered_long_path.set_bundled_dictionary_path(dictionary_path));
    registered_long_path.set_user_dictionary({
        {"わたし", "私", 3}, {"ともだち", "友達", 3},
    });
    for (const char value : std::string("watashihakyouToukyounoekidetomodachitoaimashita")) {
        registered_long_path.append_ascii(value);
    }
    assert(std::any_of(registered_long_path.candidates().begin(),
        registered_long_path.candidates().end(), [](const auto &candidate) {
            return candidate.text == "私は今日東京の駅で友達と会いました";
        }));
    ImeSession stable_clause;
    assert(stable_clause.set_bundled_dictionary_path(dictionary_path));
    std::string committed_prefix;
    for (const char value : std::string("watashihakyouToukyounoekidetomodachitoaimashita")) {
        stable_clause.append_ascii(value);
        committed_prefix += stable_clause.take_completed_clause();
    }
    assert(committed_prefix == "私");
    assert(stable_clause.reading().rfind("は", 0) == 0);
    assert(stable_clause.selected_text().rfind("は", 0) == 0);
    ImeSession strong_clause;
    assert(strong_clause.set_bundled_dictionary_path(dictionary_path));
    strong_clause.set_automatic_completion_strength(4);
    assert(strong_clause.automatic_completion_strength() == 4);
    std::size_t strong_completed_at = 0;
    const std::string phrase = "watashihakyouToukyounoekidetomodachitoaimashita";
    for (std::size_t index = 0; index < phrase.size(); ++index) {
        strong_clause.append_ascii(phrase[index]);
        if (!strong_clause.take_completed_clause().empty()) {
            strong_completed_at = index + 1;
            break;
        }
    }
    assert(strong_completed_at > 0 && strong_completed_at < phrase.size());
    ImeSession disabled_clause;
    assert(disabled_clause.set_bundled_dictionary_path(dictionary_path));
    disabled_clause.set_automatic_completion_strength(0);
    for (const char value : std::string("watashihakyouToukyounoekidetomodachitoaimashita")) {
        disabled_clause.append_ascii(value);
        assert(disabled_clause.take_completed_clause().empty());
    }
    ImeSession personal_phrase;
    assert(personal_phrase.set_bundled_dictionary_path(dictionary_path));
    personal_phrase.set_user_dictionary({personal_entry});
    for (const char value : std::string("tesutokana")) personal_phrase.append_ascii(value);
    assert(std::any_of(personal_phrase.candidates().begin(), personal_phrase.candidates().end(),
        [](const keynako::Candidate &candidate) {
            return candidate.text.find("個人語") != std::string::npos;
        }));
    personal_phrase.clear();
    for (const char value : std::string("atesutoikana")) personal_phrase.append_ascii(value);
    assert(std::any_of(personal_phrase.candidates().begin(), personal_phrase.candidates().end(),
        [](const keynako::Candidate &candidate) {
            return candidate.text.find("個人語") != std::string::npos;
        }));
    ImeSession bundled_prediction;
    assert(bundled_prediction.set_bundled_dictionary_path(dictionary_path));
    for (const char value : std::string("konni")) bundled_prediction.append_ascii(value);
    assert(std::any_of(
        bundled_prediction.candidates().begin(), bundled_prediction.candidates().end(),
        [](const keynako::Candidate &candidate) {
            return candidate.source == "azookey-prediction";
        }));
    bundled.set_user_dictionary({
        {"にほん", "共有", 5, 1000.0f, 1285, 1285, true},
    });
    const auto has_combined_shared_entry = std::any_of(
        bundled.candidates().begin(), bundled.candidates().end(),
        [](const keynako::Candidate &candidate) { return candidate.text.rfind("共有", 0) == 0; });
    assert(has_combined_shared_entry);
    return 0;
}
