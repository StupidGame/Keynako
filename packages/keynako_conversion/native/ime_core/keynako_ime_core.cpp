#include "keynako_ime_core.h"

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <tuple>
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

std::string convert_kana(const std::string &value, bool katakana) {
    std::string result;
    for (std::size_t i = 0; i < value.size();) {
        const unsigned char first = static_cast<unsigned char>(value[i]);
        if (first < 0x80) { result.push_back(value[i++]); continue; }
        if (i + 2 < value.size() && (first & 0xf0) == 0xe0) {
            int code = ((first & 0x0f) << 12) |
                       ((static_cast<unsigned char>(value[i + 1]) & 0x3f) << 6) |
                       (static_cast<unsigned char>(value[i + 2]) & 0x3f);
            if (katakana && code >= 0x3041 && code <= 0x3096) code += 0x60;
            if (!katakana && code >= 0x30a1 && code <= 0x30f6) code -= 0x60;
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

std::string hiragana_to_katakana(const std::string &value) {
    return convert_kana(value, true);
}

std::size_t utf8_character_count(const std::string &value) {
    return static_cast<std::size_t>(std::count_if(value.begin(), value.end(),
        [](unsigned char byte) { return (byte & 0xc0) != 0x80; }));
}

void append_unique(std::vector<Candidate> &out, std::unordered_set<std::string> &seen,
                   std::string text, const char *source) {
    if (!text.empty() && seen.insert(text).second) out.push_back({std::move(text), source});
}

bool ascii_digits(const std::string &value) {
    return !value.empty() && std::all_of(value.begin(), value.end(),
        [](unsigned char character) { return character >= '0' && character <= '9'; });
}

std::vector<std::string> email_address_candidates(const std::string &input) {
    static const std::vector<std::string> domains = {
        "@gmail.com", "@icloud.com", "@yahoo.co.jp", "@au.com",
        "@docomo.ne.jp", "@excite.co.jp", "@ezweb.ne.jp", "@googlemail.com",
        "@hotmail.co.jp", "@hotmail.com", "@i.softbank.jp", "@live.jp",
        "@me.com", "@mineo.jp", "@nifty.com", "@outlook.com", "@outlook.jp",
        "@softbank.ne.jp", "@yahoo.ne.jp", "@ybb.ne.jp", "@ymobile.ne.jp",
    };
    const auto at = input.rfind('@');
    if (at == std::string::npos) return {};
    const std::string local = input.substr(0, at);
    if (!std::all_of(local.begin(), local.end(), [](unsigned char value) {
            return std::isalnum(value) || value == '.' || value == '_' ||
                value == '+' || value == '-';
        })) return {};
    std::string prefix = input.substr(at);
    std::transform(prefix.begin(), prefix.end(), prefix.begin(),
        [](unsigned char value) { return static_cast<char>(std::tolower(value)); });
    std::vector<std::string> result;
    for (const auto &domain : domains) {
        if (domain.rfind(prefix, 0) == 0) result.push_back(local + domain);
    }
    return result;
}

std::vector<std::string> special_complete_candidates(const std::string &reading) {
    std::vector<std::string> result;
    const bool negative = !reading.empty() && reading.front() == '-';
    const std::string unsigned_text = negative ? reading.substr(1) : reading;
    const auto dot = unsigned_text.find('.');
    const std::string integer = unsigned_text.substr(0, dot);
    const std::string fractional = dot == std::string::npos ? "" : unsigned_text.substr(dot + 1);
    if (ascii_digits(integer) &&
        (dot == std::string::npos ||
         (ascii_digits(fractional) && fractional.find('.') == std::string::npos))) {
        if (integer.size() > 3) {
            std::string grouped;
            for (std::size_t index = 0; index < integer.size(); ++index) {
                if (index > 0 && (integer.size() - index) % 3 == 0) grouped.push_back(',');
                grouped.push_back(integer[index]);
            }
            result.push_back((negative ? "-" : "") + grouped +
                (dot == std::string::npos ? "" : "." + fractional));
        }
        if (!negative && dot == std::string::npos && integer.size() >= 3 && integer.size() <= 4) {
            const int hours = std::stoi(integer.substr(0, integer.size() - 2));
            const int minutes = std::stoi(integer.substr(integer.size() - 2));
            if (hours <= 24 && minutes <= 59) {
                result.push_back(integer.substr(0, integer.size() - 2) + ":" +
                    integer.substr(integer.size() - 2));
            }
        }
    }
    const std::string year_suffix = "ねん";
    if (reading.size() == 4 + year_suffix.size() &&
        reading.compare(4, year_suffix.size(), year_suffix) == 0 &&
        ascii_digits(reading.substr(0, 4))) {
        const int year = std::stoi(reading.substr(0, 4));
        const std::vector<std::tuple<int, int, std::string>> eras = {
            {2019, 2018, "令和"}, {1989, 1988, "平成"},
            {1926, 1925, "昭和"}, {1912, 1911, "大正"}, {1868, 1867, "明治"},
        };
        for (const auto &[start, offset, name] : eras) {
            if (year >= start) {
                result.push_back(name + (year == start ? "元" : std::to_string(year - offset)) + "年");
                break;
            }
        }
        if (year == 2019) result.push_back("平成31年");
        if (year == 1989) result.push_back("昭和64年");
        if (year == 1926) result.push_back("大正15年");
        if (year == 1912) result.push_back("明治45年");
        if (year == 1868) result.push_back("慶應4年");
    }
    if (reading.size() > year_suffix.size() &&
        reading.compare(reading.size() - year_suffix.size(), year_suffix.size(), year_suffix) == 0) {
        const std::vector<std::pair<std::string, int>> eras = {
            {"めいじ", 1867}, {"たいしょう", 1911}, {"しょうわ", 1925},
            {"へいせい", 1988}, {"れいわ", 2018},
        };
        for (const auto &[name, offset] : eras) {
            if (reading.rfind(name, 0) != 0) continue;
            const auto year = reading.substr(name.size(),
                reading.size() - name.size() - year_suffix.size());
            if (year == "がん") result.push_back(std::to_string(offset + 1) + "年");
            else if (year.size() <= 2 && ascii_digits(year)) {
                result.push_back(std::to_string(offset + std::stoi(year)) + "年");
            }
            break;
        }
    }
    return result;
}

std::vector<std::string> dictionary_combinations(
    const std::string &reading, const std::vector<DictionaryEntry> &entries) {
    struct Match { std::size_t end; std::string value; int score; bool registered; };
    struct Path { std::string text; int score; int words; int registered_words; };
    if (reading.empty() || entries.empty()) return {};
    std::vector<std::vector<Match>> matches(reading.size());
    bool registered_match = false;
    const auto add = [&](const std::string &ruby, const std::string &value,
                         int importance, bool registered) {
        if (ruby.empty() || value.empty() || ruby.size() > reading.size()) return;
        std::size_t start = reading.find(ruby);
        while (start != std::string::npos) {
            matches[start].push_back({start + ruby.size(), value,
                (registered ? static_cast<int>(utf8_character_count(ruby)) * 18 - 28
                            : static_cast<int>(utf8_character_count(ruby)) * 15 - 30)
                    + std::clamp(importance, 1, 5) * 4,
                registered});
            if (registered) registered_match = true;
            start = reading.find(ruby, start + 1);
        }
    };
    for (const auto &entry : entries) {
        add(convert_kana(entry.reading, false), entry.value, entry.importance, true);
    }
    if (!registered_match) return {};
    for (const auto &[ruby, values] : kDictionary) {
        for (std::size_t i = 0; i < std::min<std::size_t>(2, values.size()); ++i) {
            add(ruby, values[i], 3, false);
        }
    }

    std::vector<std::vector<Path>> beams(reading.size() + 1);
    beams[0].push_back({"", 0, 0, 0});
    const auto by_score = [](const Path &left, const Path &right) {
        return left.score > right.score;
    };
    const auto push = [&](std::size_t end, Path path) {
        auto &paths = beams[end];
        paths.push_back(std::move(path));
        if (paths.size() > 48) {
            std::stable_sort(paths.begin(), paths.end(), by_score);
            paths.resize(16);
        }
    };
    for (std::size_t index = 0; index < reading.size(); ++index) {
        auto current = beams[index];
        std::stable_sort(current.begin(), current.end(), by_score);
        if (current.size() > 16) current.resize(16);
        const unsigned char first = static_cast<unsigned char>(reading[index]);
        const std::size_t step = first < 0x80 ? 1 : (first & 0xe0) == 0xc0 ? 2
            : (first & 0xf0) == 0xe0 ? 3 : (first & 0xf8) == 0xf0 ? 4 : 1;
        const std::size_t next = std::min(reading.size(), index + step);
        for (const auto &path : current) {
            push(next, {path.text + reading.substr(index, next - index),
                path.score - 3, path.words, path.registered_words});
            for (const auto &match : matches[index]) {
                push(match.end, {path.text + match.value, path.score + match.score,
                    path.words + 1, path.registered_words + (match.registered ? 1 : 0)});
            }
        }
    }
    auto ranked = beams.back();
    std::stable_sort(ranked.begin(), ranked.end(), by_score);
    std::vector<std::string> result;
    std::unordered_set<std::string> seen;
    for (const auto &path : ranked) {
        if (path.words < 2 || path.registered_words < 1 || path.text == reading ||
            !seen.insert(path.text).second) continue;
        result.push_back(path.text);
        if (result.size() >= 8) break;
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

bool is_known_roman_word(const std::string &roman) {
    return kDictionary.find(ImeSession::roman_to_hiragana(roman)) != kDictionary.end();
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
    if (indivisible_words.count(segment) != 0 || is_known_roman_word(segment)) return start;

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
            segment.compare(segment.size() - suffix.size(), suffix.size(), suffix) == 0 &&
            (suffix == "wo" || is_known_roman_word(segment.substr(0, segment.size() - suffix.size())))) {
            return content_end - suffix.size();
        }
    }
    for (const auto &particle : particles) {
        const std::size_t index = segment.rfind(particle);
        if (index != std::string::npos && index >= 2 &&
            segment.size() - index - particle.size() >= 2 &&
            (particle == "wo" ||
             (is_known_roman_word(segment.substr(0, index)) &&
              is_known_roman_word(segment.substr(index + particle.size()))))) {
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

std::string ImeSession::learning_key() const {
    if (mode_ == InputMode::japanese) return reading_;
    auto normalized = raw_input_;
    std::transform(normalized.begin(), normalized.end(), normalized.begin(),
        [](unsigned char value) { return static_cast<char>(std::tolower(value)); });
    return "english:" + normalized;
}

void ImeSession::learn_selected() {
    if (mode_ != InputMode::japanese || raw_input_.empty() || candidates_.empty()) return;
    const auto key = learning_key();
    const auto text = selected_text();
    if (text.empty()) return;
    auto &scores = learning_[key];
    if (converting_ || selected_index_ != 0) {
        int highest = 0;
        for (auto &[word, score] : scores) {
            if (word != text) score /= 2;
            highest = std::max(highest, score);
        }
        scores[text] = std::min(32, highest + 4);
    } else {
        scores[text] = std::min(32, scores[text] + 1);
    }
    learning_order_.erase(std::remove(learning_order_.begin(), learning_order_.end(), key), learning_order_.end());
    learning_order_.push_back(key);
    if (learning_order_.size() > 4096) {
        learning_.erase(learning_order_.front());
        learning_order_.pop_front();
    }
}

void ImeSession::prioritize_learning() {
    const auto found = learning_.find(learning_key());
    if (found == learning_.end()) return;
    const auto score = [&](const Candidate &candidate) {
        const auto entry = found->second.find(candidate.text);
        return entry == found->second.end() ? 0 : entry->second;
    };
    std::stable_sort(candidates_.begin(), candidates_.end(), [&](const auto &left, const auto &right) {
        return score(left) > score(right);
    });
}
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
    const auto found = std::find_if(candidates_.begin(), candidates_.end(), [this](const Candidate &candidate) {
        return candidate.text == reading_;
    });
    if (found == candidates_.end()) return false;
    converting_ = true;
    selected_index_ = static_cast<std::size_t>(std::distance(candidates_.begin(), found));
    return true;
}
void ImeSession::set_user_dictionary(std::vector<DictionaryEntry> entries) {
    for (auto &entry : entries) entry.reading = convert_kana(entry.reading, false);
    std::stable_sort(entries.begin(), entries.end(), [](const DictionaryEntry &left, const DictionaryEntry &right) {
        if (left.importance != right.importance) return left.importance > right.importance;
        if (left.reading.size() != right.reading.size()) return left.reading.size() < right.reading.size();
        return left.reading < right.reading;
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
    const bool preserve_selection = converting_ || selected_index_ != 0;
    const auto selected = selected_text();
    candidates_.erase(std::remove_if(candidates_.begin(), candidates_.end(), [&value](const Candidate &candidate) {
        return candidate.text == value;
    }), candidates_.end());
    candidates_.insert(candidates_.begin(), {std::move(value), "zenzai"});
    prioritize_learning();
    selected_index_ = 0;
    if (preserve_selection) {
        const auto found = std::find_if(candidates_.begin(), candidates_.end(),
            [&](const auto &candidate) { return candidate.text == selected; });
        if (found != candidates_.end()) selected_index_ = static_cast<std::size_t>(found - candidates_.begin());
    }
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
        for (auto &value : email_address_candidates(raw_input_)) {
            append_unique(candidates_, seen, std::move(value), "email-prediction");
        }
        for (auto &value : special_complete_candidates(raw_input_)) {
            append_unique(candidates_, seen, std::move(value), "special");
        }
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
        if (conversion_reading.empty()) return;
        text += literal_suffix;
        append_unique(prefix_predictions, prediction_seen, std::move(text), source);
    };

    struct LearnedPrediction {
        std::string text;
        int score;
        std::size_t remaining;
    };
    std::vector<LearnedPrediction> learned_predictions;
    for (const auto &[ruby, scores] : learning_) {
        if (ruby.rfind("english:", 0) == 0 || conversion_reading.empty()) continue;
        if (ruby == reading_) {
            for (const auto &[word, score] : scores) {
                if (score > 0) append_unique(candidates_, seen, word, "learned");
            }
        } else if (ruby.size() > reading_.size() && ruby.rfind(reading_, 0) == 0) {
            for (const auto &[word, score] : scores) {
                if (score > 0) learned_predictions.push_back({word, score, ruby.size() - reading_.size()});
            }
        }
    }
    std::stable_sort(learned_predictions.begin(), learned_predictions.end(), [](const auto &left, const auto &right) {
        return left.score == right.score ? left.remaining < right.remaining : left.score > right.score;
    });
    for (const auto &entry : learned_predictions) {
        append_unique(prefix_predictions, prediction_seen, entry.text, "learned-prediction");
    }

    struct SharedPrediction {
        std::string text;
        int importance;
        std::size_t remaining;
        std::string source;
    };
    std::vector<SharedPrediction> shared_predictions;
    for (const auto &entry : user_dictionary_) {
        if (entry.reading == conversion_reading) {
            append_converted(entry.value, entry.source.c_str());
        } else if (entry.reading.size() > conversion_reading.size() &&
                   entry.reading.rfind(conversion_reading, 0) == 0) {
            shared_predictions.push_back({entry.value, entry.importance,
                utf8_character_count(entry.reading) - utf8_character_count(conversion_reading),
                entry.source == "personal" ? "personal-prediction" : "shared-prediction"});
        }
    }
    std::stable_sort(shared_predictions.begin(), shared_predictions.end(),
        [](const auto &left, const auto &right) {
            const auto left_score = std::clamp(left.importance, 1, 5) * 20 -
                static_cast<int>(std::min<std::size_t>(left.remaining, 1000)) * 4;
            const auto right_score = std::clamp(right.importance, 1, 5) * 20 -
                static_cast<int>(std::min<std::size_t>(right.remaining, 1000)) * 4;
            return left_score == right_score ? left.remaining < right.remaining
                                             : left_score > right_score;
        });
    for (const auto &entry : shared_predictions) {
        append_prediction(entry.text, entry.source.c_str());
    }
    for (auto &value : dictionary_combinations(conversion_reading, user_dictionary_)) {
        append_converted(std::move(value), "dictionary-combination");
    }
    if (bundled_dictionary_ && !conversion_reading.empty()) {
        std::vector<AzooKeyAdditionalEntry> additional_entries;
        for (const auto &entry : user_dictionary_) {
            if (entry.has_word_weight) {
                additional_entries.push_back({entry.value, entry.reading, entry.lcid,
                                              entry.rcid, entry.word_weight});
            } else if (entry.source == "personal" && !entry.reading.empty() &&
                       conversion_reading.find(entry.reading) != std::string::npos) {
                additional_entries.push_back({entry.value, entry.reading, 1285, 1285,
                                              static_cast<float>((entry.importance - 3) * 2 - 9)});
            }
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
    for (auto &value : special_complete_candidates(conversion_reading)) {
        append_converted(std::move(value), "special");
    }
    for (auto &value : email_address_candidates(conversion_input)) {
        append_prediction(std::move(value), "email-prediction");
    }
    static const auto fallback_predictions = [] {
        std::vector<std::pair<std::string, std::vector<std::string>>> entries(
            kDictionary.begin(), kDictionary.end());
        std::sort(entries.begin(), entries.end(), [](const auto &left, const auto &right) {
            if (left.first.size() != right.first.size()) return left.first.size() < right.first.size();
            return left.first < right.first;
        });
        return entries;
    }();
    for (const auto &entry : fallback_predictions) {
        if (entry.first.size() <= conversion_reading.size() ||
            entry.first.rfind(conversion_reading, 0) != 0) {
            continue;
        }
        for (const auto &value : entry.second) {
            append_prediction(value, "dictionary-prediction");
        }
    }
    const auto conversion_count = candidates_.size();
    append_unique(candidates_, seen, reading_, "reading");
    append_converted(hiragana_to_katakana(conversion_reading), "katakana");
    append_unique(candidates_, seen, raw_input_, "latin");
    const auto insertion_index = std::min(candidates_.size(),
        std::max<std::size_t>(2, std::min<std::size_t>(3, conversion_count)));
    auto insertion = candidates_.begin() + static_cast<std::ptrdiff_t>(insertion_index);
    std::size_t inserted = 0;
    for (auto &prediction : prefix_predictions) {
        if (!seen.insert(prediction.text).second) continue;
        insertion = candidates_.insert(insertion, std::move(prediction)) + 1;
        if (++inserted >= 32) break;
    }
    prioritize_learning();
}

}  // namespace keynako
