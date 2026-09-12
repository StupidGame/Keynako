#include "keynako_ime_core.h"

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <unordered_map>
#include <unordered_set>
#include <utility>

namespace keynako {
namespace {

const std::unordered_map<std::string, std::string> kRoman = {
    {"kya", "きゃ"}, {"kyu", "きゅ"}, {"kyo", "きょ"}, {"gya", "ぎゃ"}, {"gyu", "ぎゅ"}, {"gyo", "ぎょ"},
    {"sha", "しゃ"}, {"shu", "しゅ"}, {"sho", "しょ"}, {"sya", "しゃ"}, {"syu", "しゅ"}, {"syo", "しょ"},
    {"ja", "じゃ"}, {"ju", "じゅ"}, {"jo", "じょ"}, {"jya", "じゃ"}, {"jyu", "じゅ"}, {"jyo", "じょ"},
    {"cha", "ちゃ"}, {"chu", "ちゅ"}, {"cho", "ちょ"}, {"cya", "ちゃ"}, {"cyu", "ちゅ"}, {"cyo", "ちょ"},
    {"tya", "ちゃ"}, {"tyu", "ちゅ"}, {"tyo", "ちょ"}, {"nya", "にゃ"}, {"nyu", "にゅ"}, {"nyo", "にょ"},
    {"hya", "ひゃ"}, {"hyu", "ひゅ"}, {"hyo", "ひょ"}, {"bya", "びゃ"}, {"byu", "びゅ"}, {"byo", "びょ"},
    {"pya", "ぴゃ"}, {"pyu", "ぴゅ"}, {"pyo", "ぴょ"}, {"mya", "みゃ"}, {"myu", "みゅ"}, {"myo", "みょ"},
    {"rya", "りゃ"}, {"ryu", "りゅ"}, {"ryo", "りょ"}, {"fa", "ふぁ"}, {"fi", "ふぃ"}, {"fe", "ふぇ"}, {"fo", "ふぉ"},
    {"va", "ゔぁ"}, {"vi", "ゔぃ"}, {"vu", "ゔ"}, {"ve", "ゔぇ"}, {"vo", "ゔぉ"},
    {"tsa", "つぁ"}, {"tsi", "つぃ"}, {"tse", "つぇ"}, {"tso", "つぉ"}, {"she", "しぇ"}, {"che", "ちぇ"}, {"je", "じぇ"},
    {"thi", "てぃ"}, {"dhi", "でぃ"}, {"twu", "とぅ"}, {"dwu", "どぅ"}, {"kwa", "くぁ"}, {"gwa", "ぐぁ"},
    {"ye", "いぇ"}, {"wi", "うぃ"}, {"we", "うぇ"}, {"wo", "を"},
    {"ka", "か"}, {"ki", "き"}, {"ku", "く"}, {"ke", "け"}, {"ko", "こ"}, {"ga", "が"}, {"gi", "ぎ"}, {"gu", "ぐ"}, {"ge", "げ"}, {"go", "ご"},
    {"sa", "さ"}, {"si", "し"}, {"shi", "し"}, {"su", "す"}, {"se", "せ"}, {"so", "そ"}, {"za", "ざ"}, {"zi", "じ"}, {"ji", "じ"}, {"zu", "ず"}, {"ze", "ぜ"}, {"zo", "ぞ"},
    {"ta", "た"}, {"ti", "ち"}, {"chi", "ち"}, {"tu", "つ"}, {"tsu", "つ"}, {"te", "て"}, {"to", "と"}, {"da", "だ"}, {"di", "ぢ"}, {"du", "づ"}, {"de", "で"}, {"do", "ど"},
    {"na", "な"}, {"ni", "に"}, {"nu", "ぬ"}, {"ne", "ね"}, {"no", "の"}, {"ha", "は"}, {"hi", "ひ"}, {"hu", "ふ"}, {"fu", "ふ"}, {"he", "へ"}, {"ho", "ほ"},
    {"ba", "ば"}, {"bi", "び"}, {"bu", "ぶ"}, {"be", "べ"}, {"bo", "ぼ"}, {"pa", "ぱ"}, {"pi", "ぴ"}, {"pu", "ぷ"}, {"pe", "ぺ"}, {"po", "ぽ"},
    {"ma", "ま"}, {"mi", "み"}, {"mu", "む"}, {"me", "め"}, {"mo", "も"}, {"ya", "や"}, {"yu", "ゆ"}, {"yo", "よ"},
    {"ra", "ら"}, {"ri", "り"}, {"ru", "る"}, {"re", "れ"}, {"ro", "ろ"}, {"wa", "わ"}, {"nn", "ん"},
    {"la", "ぁ"}, {"li", "ぃ"}, {"lu", "ぅ"}, {"le", "ぇ"}, {"lo", "ぉ"}, {"xa", "ぁ"}, {"xi", "ぃ"}, {"xu", "ぅ"}, {"xe", "ぇ"}, {"xo", "ぉ"},
    {"lya", "ゃ"}, {"lyu", "ゅ"}, {"lyo", "ょ"}, {"xya", "ゃ"}, {"xyu", "ゅ"}, {"xyo", "ょ"}, {"ltu", "っ"}, {"xtu", "っ"},
    {"a", "あ"}, {"i", "い"}, {"u", "う"}, {"e", "え"}, {"o", "お"}, {"-", "ー"}, {",", "、"}, {".", "。"},
    {"!", "！"}, {"?", "？"},
};

const std::unordered_map<std::string, std::vector<std::string>> kDictionary = {
    {"あい", {"愛", "藍", "相"}}, {"あう", {"会う", "合う", "遭う"}}, {"あさ", {"朝", "麻"}},
    {"あした", {"明日"}}, {"ありがとう", {"ありがとう", "有難う"}}, {"いま", {"今", "居間"}},
    {"うえ", {"上"}}, {"おはよう", {"おはよう", "お早う"}}, {"おねがい", {"お願い"}},
    {"かく", {"書く", "描く", "核"}}, {"きょう", {"今日", "京"}}, {"こんにちは", {"こんにちは"}},
    {"ことば", {"言葉"}}, {"じかん", {"時間"}}, {"すき", {"好き"}}, {"せってい", {"設定"}},
    {"だいじょうぶ", {"大丈夫"}}, {"つかう", {"使う"}}, {"でんわ", {"電話"}},
    {"にほん", {"日本", "二本"}}, {"にほんご", {"日本語"}}, {"へんかん", {"変換"}},
    {"ほんじつ", {"本日"}}, {"みる", {"見る", "観る"}}, {"もじ", {"文字"}},
    {"よろしく", {"よろしく", "宜しく"}}, {"わたし", {"私"}},
};

std::string hiragana_to_katakana(const std::string &value) {
    std::string result;
    for (std::size_t i = 0; i < value.size();) {
        const unsigned char first = static_cast<unsigned char>(value[i]);
        if (first < 0x80) { result.push_back(value[i++]); continue; }
        if (i + 2 < value.size() && (first & 0xf0) == 0xe0) {
            int code = ((first & 0x0f) << 12) |
                       ((static_cast<unsigned char>(value[i + 1]) & 0x3f) << 6) |
                       (static_cast<unsigned char>(value[i + 2]) & 0x3f);
            if (code >= 0x3041 && code <= 0x3096) code += 0x60;
            result.push_back(static_cast<char>(0xe0 | ((code >> 12) & 0x0f)));
            result.push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3f)));
            result.push_back(static_cast<char>(0x80 | (code & 0x3f)));
            i += 3;
            continue;
        }
        result.push_back(value[i++]);
    }
    return result;
}

void append_unique(std::vector<Candidate> &out, std::unordered_set<std::string> &seen,
                   std::string text, const char *source) {
    if (!text.empty() && seen.insert(text).second) out.push_back({std::move(text), source});
}

struct CombinationEntry {
    std::string reading;
    std::string text;
    int score = 0;
};

struct CombinationPath {
    std::string text;
    std::size_t converted_length = 0;
    int segment_count = 0;
    int score = 0;
};

bool better_combination_path(const CombinationPath &left,
                             const CombinationPath &right) {
    if (left.converted_length != right.converted_length) {
        return left.converted_length > right.converted_length;
    }
    if (left.score != right.score) return left.score > right.score;
    return left.segment_count > right.segment_count;
}

std::size_t next_utf8_position(const std::string &value, std::size_t start) {
    if (start >= value.size()) return value.size();
    const unsigned char first = static_cast<unsigned char>(value[start]);
    const std::size_t length = first < 0x80 ? 1 :
        (first & 0xe0) == 0xc0 ? 2 : (first & 0xf0) == 0xe0 ? 3 :
        (first & 0xf8) == 0xf0 ? 4 : 1;
    return std::min(value.size(), start + length);
}

void trim_combination_paths(std::vector<CombinationPath> &paths) {
    constexpr std::size_t kCombinationBeamWidth = 48;
    if (paths.size() <= kCombinationBeamWidth) return;
    std::stable_sort(paths.begin(), paths.end(), better_combination_path);
    std::unordered_set<std::string> seen;
    std::vector<CombinationPath> trimmed;
    for (auto &path : paths) {
        const std::string key = path.text + '\0' +
            std::to_string(path.converted_length) + '\0' +
            std::to_string(path.segment_count);
        if (seen.insert(key).second) trimmed.push_back(std::move(path));
        if (trimmed.size() >= kCombinationBeamWidth) break;
    }
    paths = std::move(trimmed);
}

std::vector<std::string> combined_dictionary_candidates(
    const std::string &reading,
    const std::vector<DictionaryEntry> &user_dictionary) {
    if (reading.empty()) return {};
    std::vector<CombinationEntry> entries;
    for (const auto &entry : user_dictionary) {
        if (!entry.reading.empty() && !entry.value.empty()) {
            entries.push_back({entry.reading, entry.value,
                               100 + std::clamp(entry.importance, 1, 5) * 20});
        }
    }
    for (const auto &entry : kDictionary) {
        for (const auto &text : entry.second) {
            entries.push_back({entry.first, text, 100});
        }
    }

    std::vector<std::vector<CombinationPath>> paths(reading.size() + 1);
    paths.front().push_back({"", 0, 0, 0});
    for (std::size_t start = 0; start < reading.size(); ++start) {
        if (paths[start].empty()) continue;
        const auto previous = paths[start];
        std::unordered_set<std::size_t> touched_ends;

        const std::size_t fallback_end = next_utf8_position(reading, start);
        touched_ends.insert(fallback_end);
        for (const auto &path : previous) {
            paths[fallback_end].push_back({
                path.text + reading.substr(start, fallback_end - start),
                path.converted_length, path.segment_count, path.score - 8});
        }

        for (const auto &entry : entries) {
            if (entry.reading.size() > reading.size() - start ||
                reading.compare(start, entry.reading.size(), entry.reading) != 0) {
                continue;
            }
            const std::size_t end = start + entry.reading.size();
            touched_ends.insert(end);
            for (const auto &path : previous) {
                paths[end].push_back({path.text + entry.text,
                    path.converted_length + entry.reading.size(),
                    path.segment_count + 1, path.score + entry.score});
            }
        }
        for (const auto end : touched_ends) trim_combination_paths(paths[end]);
    }

    auto completed = std::move(paths.back());
    std::stable_sort(completed.begin(), completed.end(), better_combination_path);
    std::unordered_set<std::string> seen;
    std::vector<std::string> result;
    for (auto &path : completed) {
        if (path.segment_count < 2 || path.text.empty() ||
            !seen.insert(path.text).second) {
            continue;
        }
        result.push_back(std::move(path.text));
        if (result.size() >= 24) break;
    }
    return result;
}

bool is_literal_candidate_suffix(char value) {
    return value == '!' || value == '?' || value == '/';
}

std::string display_ascii(char value, InputMode mode) {
    if (mode == InputMode::japanese) {
        if (value == '!') return "！";
        if (value == '?') return "？";
    }
    return std::string(1, value);
}

std::string display_literal_suffix(const std::string &value, InputMode mode) {
    std::string result;
    for (const char character : value) {
        result += display_ascii(character, mode);
    }
    return result;
}

int word_character_class(unsigned char value) {
    if (std::isspace(value)) return 0;
    if (std::isalnum(value) || value == '_') return 1;
    return 2;
}

std::size_t ascii_word_delete_start(const std::string &input,
                                    std::size_t lower_bound) {
    std::size_t start = input.size();
    while (start > lower_bound &&
           word_character_class(static_cast<unsigned char>(input[start - 1])) == 0) {
        --start;
    }
    if (start > lower_bound) {
        const int target_class = word_character_class(
            static_cast<unsigned char>(input[start - 1]));
        while (start > lower_bound &&
               word_character_class(static_cast<unsigned char>(input[start - 1])) ==
                   target_class) {
            --start;
        }
    }
    return start;
}

std::size_t japanese_roman_word_delete_start(const std::string &input) {
    std::size_t content_end = input.size();
    while (content_end > 0 &&
           word_character_class(static_cast<unsigned char>(input[content_end - 1])) == 0) {
        --content_end;
    }
    if (content_end == 0) return 0;
    const std::string content = input.substr(0, content_end);
    const std::size_t start = ascii_word_delete_start(content, 0);
    if (start >= content.size() ||
        word_character_class(static_cast<unsigned char>(content.back())) != 1) {
        return start;
    }

    std::string segment = content.substr(start);
    std::transform(segment.begin(), segment.end(), segment.begin(),
                   [](unsigned char value) {
                       return static_cast<char>(std::tolower(value));
                   });
    static const std::unordered_set<std::string> indivisible_words = {
        "konnichiha", "konbanha", "arigatou", "ohayou",
    };
    if (indivisible_words.count(segment) != 0) return start;

    static const std::vector<std::string> auxiliaries = {
        "masendeshita", "mashou", "mashita", "masen", "masu",
        "deshita", "deshou", "desu", "datta", "darou", "nai", "tai",
    };
    static const std::vector<std::string> particles = {
        "kara", "made", "yori", "node", "noni", "deha", "niha", "toha",
        "tte", "wo", "ga", "ha", "mo", "no", "ni", "he", "de", "to", "ya",
    };
    for (const auto &suffix : auxiliaries) {
        if (segment.size() > suffix.size() &&
            segment.compare(segment.size() - suffix.size(), suffix.size(), suffix) == 0) {
            return content_end - suffix.size();
        }
    }
    for (const auto &suffix : particles) {
        if (segment.size() > suffix.size() &&
            segment.compare(segment.size() - suffix.size(), suffix.size(), suffix) == 0) {
            return content_end - suffix.size();
        }
    }
    for (const auto &particle : particles) {
        const std::size_t index = segment.rfind(particle);
        if (index != std::string::npos && index >= 2 &&
            segment.size() - index - particle.size() >= 2) {
            return start + index + particle.size();
        }
    }
    return start;
}

std::size_t word_delete_start(const std::string &input, InputMode mode,
                              std::size_t literal_suffix_start) {
    const bool has_literal_suffix =
        literal_suffix_start != std::string::npos &&
        literal_suffix_start < input.size();
    if (mode == InputMode::japanese && !has_literal_suffix) {
        return japanese_roman_word_delete_start(input);
    }
    return ascii_word_delete_start(
        input, has_literal_suffix ? literal_suffix_start : 0);
}

}  // namespace

void ImeSession::set_mode(InputMode mode) {
    if (mode_ == mode) return;
    const bool was_converting = converting_;
    mode_ = mode;
    pending_word_delete_start_ = std::string::npos;
    live_conversion_suspended_ = false;
    rebuild_candidates();
    converting_ = was_converting && !candidates_.empty();
}
void ImeSession::set_live_conversion(bool enabled) { live_conversion_ = enabled; live_conversion_suspended_ = false; }
void ImeSession::append_ascii(char value) {
    append_ascii_internal(value, is_literal_candidate_suffix(value), false);
}

void ImeSession::append_literal_ascii(char value) {
    append_ascii_internal(value, true, true);
}

void ImeSession::append_ascii_internal(char value, bool preserve_selection,
                                       bool extend_literal_suffix) {
    preserve_selection = preserve_selection && !candidates_.empty();
    const bool was_converting = converting_;
    const std::size_t previous_selected_index = selected_index_;
    const std::string selected_prefix = preserve_selection
        ? candidates_[selected_index_].text
        : std::string{};
    const std::string selected_source = preserve_selection
        ? candidates_[selected_index_].source
        : std::string{};
    converting_ = false;
    live_conversion_suspended_ = false;
    pending_word_delete_start_ = std::string::npos;
    if (extend_literal_suffix && literal_suffix_start_ == std::string::npos) {
        literal_suffix_start_ = raw_input_.size();
    }
    raw_input_.push_back(value);
    rebuild_candidates();
    if (!preserve_selection) return;

    const std::string expected = selected_prefix + display_ascii(value, mode_);
    const auto found = std::find_if(
        candidates_.begin(), candidates_.end(),
        [&expected](const Candidate &candidate) {
            return candidate.text == expected;
        });
    if (found != candidates_.end()) {
        selected_index_ = static_cast<std::size_t>(
            std::distance(candidates_.begin(), found));
    } else {
        const std::size_t insertion_index =
            std::min(previous_selected_index, candidates_.size());
        candidates_.insert(candidates_.begin() + insertion_index,
                           {expected, selected_source});
        selected_index_ = insertion_index;
    }
    converting_ = was_converting;
}
void ImeSession::backspace() {
    if (raw_input_.empty()) {
        pending_word_delete_start_ = std::string::npos;
        return;
    }
    pending_word_delete_start_ =
        word_delete_start(raw_input_, mode_, literal_suffix_start_);
    const bool preserve_selection = !candidates_.empty() &&
        (has_literal_suffix() ||
         is_literal_candidate_suffix(raw_input_.back()));
    const bool was_converting = converting_;
    const std::size_t previous_selected_index = selected_index_;
    std::string expected = preserve_selection
        ? candidates_[selected_index_].text
        : std::string{};
    const std::string selected_source = preserve_selection
        ? candidates_[selected_index_].source
        : std::string{};
    if (preserve_selection && !expected.empty()) {
        const std::string suffix = display_ascii(raw_input_.back(), mode_);
        if (expected.size() >= suffix.size() &&
            expected.compare(expected.size() - suffix.size(), suffix.size(),
                             suffix) == 0) {
            expected.resize(expected.size() - suffix.size());
        }
    }
    converting_ = false;
    live_conversion_suspended_ = false;
    raw_input_.pop_back();
    if (literal_suffix_start_ != std::string::npos &&
        raw_input_.size() <= literal_suffix_start_) {
        literal_suffix_start_ = std::string::npos;
    }
    rebuild_candidates();
    if (!preserve_selection || expected.empty()) return;
    const auto found = std::find_if(
        candidates_.begin(), candidates_.end(),
        [&expected](const Candidate &candidate) {
            return candidate.text == expected;
        });
    if (found != candidates_.end()) {
        selected_index_ = static_cast<std::size_t>(
            std::distance(candidates_.begin(), found));
    } else {
        const std::size_t insertion_index =
            std::min(previous_selected_index, candidates_.size());
        candidates_.insert(candidates_.begin() + insertion_index,
                           {expected, selected_source});
        selected_index_ = insertion_index;
    }
    converting_ = was_converting;
}

void ImeSession::backspace_word() {
    if (raw_input_.empty()) {
        pending_word_delete_start_ = std::string::npos;
        return;
    }
    const std::size_t recalculated =
        word_delete_start(raw_input_, mode_, literal_suffix_start_);
    const std::size_t start =
        pending_word_delete_start_ != std::string::npos &&
                pending_word_delete_start_ <= raw_input_.size()
            ? pending_word_delete_start_
            : recalculated;
    pending_word_delete_start_ = std::string::npos;
    // If the suffix consisted only of separators, remove the suffix boundary
    // too. Otherwise it continues to protect the converted Japanese prefix.
    raw_input_.resize(start);
    if (literal_suffix_start_ != std::string::npos &&
        raw_input_.size() <= literal_suffix_start_) {
        literal_suffix_start_ = std::string::npos;
    }
    converting_ = false;
    live_conversion_suspended_ = false;
    rebuild_candidates();
}
void ImeSession::clear() { raw_input_.clear(); reading_.clear(); candidates_.clear(); selected_index_ = 0; converting_ = false; live_conversion_suspended_ = false; literal_suffix_start_ = std::string::npos; pending_word_delete_start_ = std::string::npos; }
bool ImeSession::begin_conversion() {
    if (raw_input_.empty() || candidates_.empty()) return false;
    converting_ = true;
    live_conversion_suspended_ = false;
    selected_index_ = 0;
    return true;
}
bool ImeSession::cancel_conversion() {
    if (!converting_) return false;
    converting_ = false;
    live_conversion_suspended_ = true;
    selected_index_ = 0;
    return true;
}
bool ImeSession::select_candidate(std::size_t index) {
    if (!converting_ || index >= candidates_.size()) return false;
    selected_index_ = index;
    return true;
}
bool ImeSession::select_reading() {
    if (raw_input_.empty()) return false;
    const auto found = std::find_if(candidates_.begin(), candidates_.end(), [](const Candidate &candidate) {
        return candidate.source == "reading" || candidate.source == "english";
    });
    if (found == candidates_.end()) return false;
    converting_ = true;
    selected_index_ = static_cast<std::size_t>(std::distance(candidates_.begin(), found));
    return true;
}
void ImeSession::set_user_dictionary(std::vector<DictionaryEntry> entries) {
    std::stable_sort(entries.begin(), entries.end(), [](const DictionaryEntry &left, const DictionaryEntry &right) {
        if (left.reading != right.reading) return left.reading < right.reading;
        return left.importance > right.importance;
    });
    user_dictionary_ = std::move(entries);
    if (!raw_input_.empty()) rebuild_candidates();
}
bool ImeSession::set_bundled_dictionary_path(const std::string &utf8_path) {
    if (utf8_path.empty()) {
        bundled_dictionary_.reset();
        if (!raw_input_.empty()) rebuild_candidates();
        return false;
    }
    auto dictionary = std::make_unique<AzooKeyDictionary>(std::filesystem::u8path(utf8_path));
    if (!dictionary->available()) return false;
    bundled_dictionary_ = std::move(dictionary);
    if (!raw_input_.empty()) rebuild_candidates();
    return true;
}
std::string ImeSession::display_text() const { return (converting_ || (live_conversion_ && !live_conversion_suspended_)) && !candidates_.empty() ? candidates_[selected_index_].text : reading_; }
std::string ImeSession::selected_text() const { return candidates_.empty() ? reading_ : candidates_[selected_index_].text; }
void ImeSession::select_next() { if (!candidates_.empty()) selected_index_ = (selected_index_ + 1) % candidates_.size(); }
void ImeSession::select_previous() { if (!candidates_.empty()) selected_index_ = (selected_index_ + candidates_.size() - 1) % candidates_.size(); }

void ImeSession::insert_zenzai_candidate(std::string value) {
    if (value.empty()) return;
    candidates_.erase(std::remove_if(candidates_.begin(), candidates_.end(), [&value](const Candidate &candidate) {
        return candidate.text == value;
    }), candidates_.end());
    candidates_.insert(candidates_.begin(), {std::move(value), "zenzai"});
    selected_index_ = 0;
}

std::string ImeSession::roman_to_hiragana(const std::string &input) {
    std::string lower = input;
    std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char value) { return static_cast<char>(std::tolower(value)); });
    std::string result;
    for (std::size_t index = 0; index < lower.size();) {
        const char current = lower[index];
        if (index + 1 < lower.size() && current == lower[index + 1] &&
            std::string("bcdfghjklmpqrstvwxyz").find(current) != std::string::npos && current != 'n') {
            result += "っ"; ++index; continue;
        }
        if (current == 'n' && index + 1 < lower.size() && std::string("aiueoyn").find(lower[index + 1]) == std::string::npos) {
            result += "ん"; ++index; continue;
        }
        bool replaced = false;
        for (const std::size_t length : {4u, 3u, 2u, 1u}) {
            if (index + length > lower.size()) continue;
            const auto found = kRoman.find(lower.substr(index, length));
            if (found == kRoman.end()) continue;
            result += found->second; index += length; replaced = true; break;
        }
        if (!replaced) result.push_back(input[index++]);
    }
    if (!lower.empty() && lower.back() == 'n' && (lower.size() < 2 || lower.substr(lower.size() - 2) != "nn") && !result.empty() && result.back() == 'n') {
        result.pop_back(); result += "ん";
    }
    return result;
}

void ImeSession::rebuild_candidates() {
    candidates_.clear(); selected_index_ = 0; converting_ = false;
    if (raw_input_.empty()) { reading_.clear(); return; }
    std::unordered_set<std::string> seen;
    std::unordered_set<std::string> prediction_seen;
    std::vector<Candidate> prefix_predictions;
    if (mode_ == InputMode::english) {
        reading_ = raw_input_;
        append_unique(candidates_, seen, raw_input_, "english");
        std::string title = raw_input_; title[0] = static_cast<char>(std::toupper(static_cast<unsigned char>(title[0])));
        append_unique(candidates_, seen, std::move(title), "english-title");
        std::string upper = raw_input_;
        std::transform(upper.begin(), upper.end(), upper.begin(), [](unsigned char value) { return static_cast<char>(std::toupper(value)); });
        append_unique(candidates_, seen, std::move(upper), "english-upper");
        return;
    }

    // Literal punctuation terminates the reading rather than becoming part of
    // its dictionary key. Keep it on every candidate so adding punctuation
    // cannot replace the text already shown by live conversion.
    std::string conversion_input;
    std::string literal_suffix;
    if (literal_suffix_start_ != std::string::npos &&
        literal_suffix_start_ <= raw_input_.size()) {
        conversion_input = raw_input_.substr(0, literal_suffix_start_);
        literal_suffix = raw_input_.substr(literal_suffix_start_);
    } else {
        conversion_input = raw_input_;
        while (!conversion_input.empty() &&
               is_literal_candidate_suffix(conversion_input.back())) {
            literal_suffix.push_back(conversion_input.back());
            conversion_input.pop_back();
        }
        std::reverse(literal_suffix.begin(), literal_suffix.end());
    }
    const std::string conversion_reading = roman_to_hiragana(conversion_input);
    literal_suffix = display_literal_suffix(literal_suffix, mode_);
    reading_ = conversion_reading + literal_suffix;
    const auto append_converted = [&](std::string text, const char *source) {
        text += literal_suffix;
        append_unique(candidates_, seen, std::move(text), source);
    };
    const auto append_prediction = [&](std::string text, const char *source) {
        text += literal_suffix;
        append_unique(prefix_predictions, prediction_seen, std::move(text), source);
    };

    for (const auto &entry : user_dictionary_) {
        if (entry.reading == conversion_reading) {
            append_converted(entry.value, "shared");
        } else if (entry.reading.size() > conversion_reading.size() &&
                   entry.reading.rfind(conversion_reading, 0) == 0) {
            append_prediction(entry.value, "shared-prediction");
        }
    }
    if (bundled_dictionary_ && !conversion_reading.empty()) {
        std::vector<AzooKeyAdditionalEntry> additional_entries;
        for (const auto &entry : user_dictionary_) {
            additional_entries.push_back({entry.value, entry.reading, entry.lcid,
                entry.rcid, entry.has_word_weight
                    ? entry.word_weight
                    : -15.0f + std::clamp(entry.importance, 1, 5) * 2.0f});
        }
        for (auto &value : bundled_dictionary_->candidates(
                 conversion_reading, 48, additional_entries)) {
            append_converted(std::move(value), "azookey");
        }
        for (auto &value : bundled_dictionary_->predictions(
                 conversion_reading, 32, additional_entries)) {
            append_prediction(std::move(value), "azookey-prediction");
        }
    }
    const auto dictionary = kDictionary.find(conversion_reading);
    if (dictionary != kDictionary.end()) {
        for (const auto &value : dictionary->second) {
            append_converted(value, "dictionary");
        }
    }
    for (auto &value : combined_dictionary_candidates(
             conversion_reading, user_dictionary_)) {
        append_converted(std::move(value), "combination");
    }
    for (const auto &entry : kDictionary) {
        if (entry.first.size() <= conversion_reading.size() ||
            entry.first.rfind(conversion_reading, 0) != 0) {
            continue;
        }
        for (const auto &value : entry.second) {
            append_prediction(value, "dictionary-prediction");
        }
    }
    append_unique(candidates_, seen, reading_, "reading");
    append_converted(hiragana_to_katakana(conversion_reading), "katakana");
    append_unique(candidates_, seen, raw_input_, "latin");
    auto insertion = candidates_.begin() +
        static_cast<std::ptrdiff_t>(std::min<std::size_t>(2, candidates_.size()));
    std::size_t inserted = 0;
    for (auto &prediction : prefix_predictions) {
        if (!seen.insert(prediction.text).second) continue;
        insertion = candidates_.insert(insertion, std::move(prediction)) + 1;
        if (++inserted >= 32) break;
    }
}

}  // namespace keynako
