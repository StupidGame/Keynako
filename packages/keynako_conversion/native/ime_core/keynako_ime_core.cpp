#include "keynako_ime_core.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstring>
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

bool is_single_hiragana_kana(const std::string &value) {
    if (value.size() != 3) return false;
    const auto first = static_cast<unsigned char>(value[0]);
    const auto second = static_cast<unsigned char>(value[1]);
    const auto third = static_cast<unsigned char>(value[2]);
    if (first != 0xe3 || (second & 0xc0) != 0x80 || (third & 0xc0) != 0x80) return false;
    const char32_t code = ((first & 0x0f) << 12) | ((second & 0x3f) << 6) | (third & 0x3f);
    return code >= 0x3041 && code <= 0x3096;
}

bool mixes_hiragana_and_katakana(const std::string &value) {
    bool hiragana = false;
    bool katakana = false;
    for (std::size_t index = 0; index + 2 < value.size(); ++index) {
        const auto first = static_cast<unsigned char>(value[index]);
        if (first != 0xe3) continue;
        const auto second = static_cast<unsigned char>(value[index + 1]);
        const auto third = static_cast<unsigned char>(value[index + 2]);
        if ((second & 0xc0) != 0x80 || (third & 0xc0) != 0x80) continue;
        const char32_t code = ((first & 0x0f) << 12) | ((second & 0x3f) << 6) | (third & 0x3f);
        hiragana = hiragana || (code >= 0x3041 && code <= 0x3096);
        katakana = katakana || (code >= 0x30a1 && code <= 0x30f6);
        index += 2;
    }
    return hiragana && katakana;
}

bool unusual_model_text(const std::string &value, const std::string &reading) {
    const bool input_has_kana_mark = reading.find(u8"\u3099") != std::string::npos ||
        reading.find(u8"\u309A") != std::string::npos;
    for (std::size_t index = 0; index < value.size();) {
        const auto first = static_cast<unsigned char>(value[index]);
        std::size_t length = 1;
        char32_t code = first;
        if (first >= 0xf0 && first <= 0xf4) { length = 4; code = first & 0x07; }
        else if (first >= 0xe0 && first <= 0xef) { length = 3; code = first & 0x0f; }
        else if (first >= 0xc2 && first <= 0xdf) { length = 2; code = first & 0x1f; }
        else if (first >= 0x80) return true;
        if (index + length > value.size()) return true;
        for (std::size_t offset = 1; offset < length; ++offset) {
            const auto next = static_cast<unsigned char>(value[index + offset]);
            if ((next & 0xc0) != 0x80) return true;
            code = (code << 6) | (next & 0x3f);
        }
        if ((length == 3 && code < 0x800) || (length == 4 && code < 0x10000) ||
            (code >= 0xd800 && code <= 0xdfff) || code > 0x10ffff ||
            code < 0x20 || (code >= 0x7f && code <= 0x9f) ||
            code == 0xfffd || (code >= 0xe000 && code <= 0xf8ff) ||
            (code >= 0x202a && code <= 0x202e) || (code >= 0x2066 && code <= 0x2069) ||
            ((code == 0x3099 || code == 0x309a) && !input_has_kana_mark)) return true;
        index += length;
    }
    return false;
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

bool is_combination_connector(const std::string &value) {
    if (value.empty()) return true;
    static const std::vector<std::string> connectors = {
        "は", "が", "を", "に", "へ", "で", "と", "も", "の", "や", "か", "ね", "よ",
        "から", "まで", "より", "だけ", "など", "しか", "こそ", "でも",
        "です", "でした", "だ", "だった", "ます", "ました",
    };
    std::vector<bool> reachable(value.size() + 1, false);
    reachable[0] = true;
    for (std::size_t index = 0; index < value.size(); ++index) {
        if (!reachable[index]) continue;
        for (const auto &connector : connectors) {
            if (value.compare(index, connector.size(), connector) == 0) {
                reachable[index + connector.size()] = true;
            }
        }
    }
    return reachable.back();
}

bool has_long_ordinary_gap_between_registered_words(
    const std::string &reading, const std::vector<DictionaryEntry> &entries) {
    struct Span { std::size_t start; std::size_t end; };
    std::vector<Span> spans;
    for (const auto &entry : entries) {
        const auto ruby = convert_kana(entry.reading, false);
        if (ruby.empty() || entry.value.empty()) continue;
        for (auto start = reading.find(ruby); start != std::string::npos;
             start = reading.find(ruby, start + 1)) {
            spans.push_back({start, start + ruby.size()});
        }
    }
    const auto valid_gap = [](const std::string &gap) {
        return is_combination_connector(gap) || utf8_character_count(gap) >= 3;
    };
    for (const auto &first : spans) for (const auto &second : spans) {
        if (second.start < first.end) continue;
        const std::vector<std::string> gaps = {
            reading.substr(0, first.start),
            reading.substr(first.end, second.start - first.end),
            reading.substr(second.end),
        };
        if (std::all_of(gaps.begin(), gaps.end(), valid_gap) &&
            std::any_of(gaps.begin(), gaps.end(), [](const auto &gap) {
                return utf8_character_count(gap) >= 3 && !is_combination_connector(gap);
            })) return true;
    }
    return false;
}

std::vector<std::string> dictionary_combinations(
    const std::string &reading, const std::vector<DictionaryEntry> &entries,
    std::size_t limit = 8, bool require_boundary_matches = true,
    int minimum_registered_words = 1) {
    struct Match { std::size_t end; std::string value; int score; bool registered; };
    struct Path {
        std::string text;
        int score;
        int words;
        int registered_words;
        bool starts_with_word;
        std::string pending_kana;
        bool valid_connectors;
    };
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
    beams[0].push_back({"", 0, 0, 0, false, "", true});
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
                path.score - 3, path.words, path.registered_words,
                path.starts_with_word, path.pending_kana + reading.substr(index, next - index),
                path.valid_connectors});
            for (const auto &match : matches[index]) {
                push(match.end, {path.text + match.value, path.score + match.score,
                    path.words + 1, path.registered_words + (match.registered ? 1 : 0),
                    path.starts_with_word || (index == 0 && path.words == 0), "",
                    path.valid_connectors && is_combination_connector(path.pending_kana)});
            }
        }
    }
    auto ranked = beams.back();
    std::stable_sort(ranked.begin(), ranked.end(), by_score);
    std::vector<std::string> result;
    std::unordered_set<std::string> seen;
    for (const auto &path : ranked) {
        if (path.words < 2 || path.registered_words < minimum_registered_words ||
            (require_boundary_matches &&
             (!path.starts_with_word || !path.valid_connectors ||
              !is_combination_connector(path.pending_kana))) ||
            path.text == reading ||
            !seen.insert(path.text).second) continue;
        result.push_back(path.text);
        if (result.size() >= limit) break;
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
    reset_stable_clause();
    const bool was_converting = converting_;
    mode_ = mode;
    pending_word_delete_start_ = std::string::npos;
    live_conversion_suspended_ = false;
    rebuild_candidates();
    converting_ = was_converting && !candidates_.empty();
}
void ImeSession::set_live_conversion(bool enabled) { live_conversion_ = enabled; live_conversion_suspended_ = false; reset_stable_clause(); }
void ImeSession::set_automatic_completion_strength(int strength) {
    automatic_completion_strength_ = std::clamp(strength, 0, 4);
    reset_stable_clause();
}
void ImeSession::append_ascii(char value) {
    append_ascii_internal(value, is_literal_candidate_suffix(value), false);
}

void ImeSession::append_literal_ascii(char value) {
    append_ascii_internal(value, true, true);
}

void ImeSession::append_ascii_internal(char value, bool preserve_selection,
                                       bool extend_literal_suffix) {
    preserve_selection = preserve_selection && !candidates_.empty() &&
        (converting_ || candidates_[selected_index_].source.find("prediction") == std::string::npos);
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
    if (!preserve_selection) {
        observe_stable_clause();
        return;
    }
    reset_stable_clause();

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
void ImeSession::reset_stable_clause() {
    stable_raw_input_.clear();
    stable_clause_reading_.clear();
    stable_clause_text_.clear();
    completed_clause_text_.clear();
    completed_clause_raw_length_ = 0;
    stable_clause_count_ = 0;
}

void ImeSession::observe_stable_clause() {
    if (mode_ != InputMode::japanese || !live_conversion_ || automatic_completion_strength_ == 0 ||
        live_conversion_suspended_ ||
        converting_ || has_literal_suffix() || candidates_.empty() || selected_index_ != 0 ||
        candidates_.front().source.find("prediction") != std::string::npos) {
        reset_stable_clause();
        return;
    }
    if (raw_input_ == stable_raw_input_) return;
    const std::string &candidate = candidates_.front().text;
    std::string clause_reading;
    std::string clause_text;
    const auto consider = [&](const std::string &ruby, const std::string &word) {
        if (word.empty() || utf8_character_count(ruby) < 2 || ruby.size() >= reading_.size() ||
            reading_.compare(0, ruby.size(), ruby) != 0 || word == ruby ||
            word.size() >= candidate.size() || candidate.compare(0, word.size(), word) != 0) return;
        if (ruby.size() > clause_reading.size()) {
            clause_reading = ruby;
            clause_text = word;
        }
    };
    for (const auto &entry : user_dictionary_) consider(entry.reading, entry.value);
    for (const auto &[ruby, values] : kDictionary) {
        for (const auto &word : values) consider(ruby, word);
    }
    if (clause_reading.empty()) {
        reset_stable_clause();
        return;
    }
    std::size_t split = std::string::npos;
    for (std::size_t index = 1; index < raw_input_.size(); ++index) {
        if (roman_to_hiragana(raw_input_.substr(0, index)) == clause_reading &&
            roman_to_hiragana(raw_input_.substr(index)) == reading_.substr(clause_reading.size())) {
            split = index;
            break;
        }
    }
    if (split == std::string::npos) {
        reset_stable_clause();
        return;
    }
    stable_clause_count_ = raw_input_.compare(0, stable_raw_input_.size(), stable_raw_input_) == 0 &&
        clause_reading == stable_clause_reading_ && clause_text == stable_clause_text_
        ? stable_clause_count_ + 1 : 1;
    stable_raw_input_ = raw_input_;
    stable_clause_reading_ = clause_reading;
    stable_clause_text_ = clause_text;
    static constexpr int thresholds[] = {0, 16, 13, 10, 6};
    if (stable_clause_count_ >= thresholds[automatic_completion_strength_]) {
        completed_clause_text_ = clause_text;
        completed_clause_raw_length_ = split;
    }
}

std::string ImeSession::take_completed_clause() {
    if (completed_clause_text_.empty() || completed_clause_raw_length_ == 0 ||
        completed_clause_raw_length_ >= raw_input_.size()) return {};
    std::string text = completed_clause_text_;
    raw_input_.erase(0, completed_clause_raw_length_);
    literal_suffix_start_ = std::string::npos;
    pending_word_delete_start_ = std::string::npos;
    converting_ = false;
    reset_stable_clause();
    rebuild_candidates();
    return text;
}

void ImeSession::backspace() {
    reset_stable_clause();
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
    reset_stable_clause();
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
void ImeSession::clear() { raw_input_.clear(); reading_.clear(); candidates_.clear(); selected_index_ = 0; converting_ = false; live_conversion_suspended_ = false; literal_suffix_start_ = std::string::npos; pending_word_delete_start_ = std::string::npos; reset_stable_clause(); }

std::string ImeSession::learning_key() const {
    if (mode_ == InputMode::japanese) return reading_;
    auto normalized = raw_input_;
    std::transform(normalized.begin(), normalized.end(), normalized.begin(),
        [](unsigned char value) { return static_cast<char>(std::tolower(value)); });
    return "english:" + normalized;
}

void ImeSession::learn_selected() {
    if (mode_ != InputMode::japanese || raw_input_.empty() || candidates_.empty()) return;
    auto key = learning_key();
    const auto &selected = candidates_[selected_index_];
    const auto text = selected.text;
    if (text.empty()) return;
    if (selected.source.find("prediction") != std::string::npos) {
        const auto full_reading = candidate_reading(selected_index_);
        if (full_reading == key) return;
        key = full_reading;
    }
    auto &scores = learning_[key];
    if (converting_ || selected_index_ != 0) {
        int highest = 0;
        for (auto &[word, score] : scores) {
            if (word != text) score /= 2;
            highest = std::max(highest, score);
        }
        scores[text] = std::min(32, highest + 4);
    } else {
        // Automatic acceptance must remain weaker than a deliberate selection.
        if (scores[text] < 4) scores[text] = std::min(3, scores[text] + 1);
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
    const auto score = [&](const Candidate &candidate) {
        // A selected completion must never become live conversion for an
        // unfinished reading on the next keystroke.
        if (candidate.source.find("prediction") != std::string::npos) return 0;
        if (found == learning_.end()) return 0;
        const auto entry = found->second.find(candidate.text);
        return entry == found->second.end() ? 0 : entry->second;
    };
    const auto priority = [](const Candidate &candidate) {
        if (candidate.source == "zenzai") return -1;
        if (candidate.source == "personal" || candidate.source == "shared" ||
            candidate.source == "dictionary-combination" ||
            candidate.source == "personal-prediction" || candidate.source == "shared-prediction") return 1;
        if (candidate.source == "learned" || candidate.source == "learned-prediction" ||
            candidate.source == "learned-combination") return 2;
        return 0;
    };
    std::stable_sort(candidates_.begin(), candidates_.end(), [&](const auto &left, const auto &right) {
        const bool left_prediction = left.source.find("prediction") != std::string::npos;
        const bool right_prediction = right.source.find("prediction") != std::string::npos;
        const auto fallback = [](const Candidate &candidate) {
            return candidate.source == "reading" || candidate.source == "katakana" ||
                candidate.source == "latin";
        };
        const int left_phase = fallback(left) ? 2 : left_prediction ? 1 : 0;
        const int right_phase = fallback(right) ? 2 : right_prediction ? 1 : 0;
        if (left_phase != right_phase) return left_phase < right_phase;
        if (priority(left) != priority(right)) return priority(left) < priority(right);
        return priority(left) == 1 && score(left) > score(right);
    });
    const bool exact_registration = std::any_of(user_dictionary_.begin(), user_dictionary_.end(), [this](const auto &entry) {
            return entry.reading == reading_;
        });
    const bool strong_learning = found != learning_.end() &&
        std::any_of(found->second.begin(), found->second.end(), [](const auto &entry) {
            return entry.second >= 4;
        });
    const auto count = utf8_character_count(reading_);
    const bool single_kana = is_single_hiragana_kana(reading_);
    const bool katakana_only = count == 2 && !candidates_.empty() &&
        candidates_.front().text == hiragana_to_katakana(reading_);
    if (!exact_registration && !strong_learning && (single_kana || katakana_only)) {
        const auto literal = std::find_if(candidates_.begin(), candidates_.end(), [this](const auto &candidate) {
            return candidate.text == reading_ && candidate.source.find("prediction") == std::string::npos;
        });
        if (literal != candidates_.end() &&
            (single_kana || static_cast<std::size_t>(literal - candidates_.begin()) <= 2)) {
            std::rotate(candidates_.begin(), literal, literal + 1);
        }
    }
    const auto katakana = hiragana_to_katakana(reading_);
    if (!reading_.empty() && katakana != reading_) {
        const auto pin = [this](const std::string &text, std::size_t latest_index) {
            const auto found = std::find_if(candidates_.begin(), candidates_.end(),
                [&text](const auto &candidate) { return candidate.text == text; });
            if (found == candidates_.end() ||
                static_cast<std::size_t>(found - candidates_.begin()) <= latest_index) return;
            std::rotate(candidates_.begin() + static_cast<std::ptrdiff_t>(latest_index),
                found, found + 1);
        };
        pin(reading_, 3);
        pin(katakana, 4);
    }
}
bool ImeSession::begin_conversion() {
    if (raw_input_.empty() || candidates_.empty()) return false;
    reset_stable_clause();
    converting_ = true;
    live_conversion_suspended_ = false;
    selected_index_ = 0;
    return true;
}
bool ImeSession::cancel_conversion() {
    if (!converting_) return false;
    reset_stable_clause();
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
std::string ImeSession::display_text() const {
    if (candidates_.empty() || (!converting_ && (!live_conversion_ || live_conversion_suspended_))) return reading_;
    const auto &candidate = candidates_[selected_index_];
    return !converting_ && candidate.source.find("prediction") != std::string::npos
        ? reading_ : candidate.text;
}
std::string ImeSession::selected_text() const { return candidates_.empty() ? reading_ : candidates_[selected_index_].text; }
std::string ImeSession::candidate_reading(std::size_t index) const {
    if (index >= candidates_.size()) return reading_;
    const auto &candidate = candidates_[index];
    if (candidate.source.find("prediction") == std::string::npos) return reading_;
    for (const auto &entry : user_dictionary_) {
        if (entry.value == candidate.text && entry.reading.size() > reading_.size() &&
            entry.reading.rfind(reading_, 0) == 0) return entry.reading;
    }
    std::string learned_reading;
    for (const auto &[ruby, scores] : learning_) {
        if (ruby.size() <= reading_.size() || ruby.rfind(reading_, 0) != 0 ||
            scores.find(candidate.text) == scores.end()) continue;
        if (learned_reading.empty() || ruby.size() < learned_reading.size()) learned_reading = ruby;
    }
    return learned_reading.empty() ? reading_ : learned_reading;
}
void ImeSession::select_next() { if (!candidates_.empty()) selected_index_ = (selected_index_ + 1) % candidates_.size(); }
void ImeSession::select_previous() { if (!candidates_.empty()) selected_index_ = (selected_index_ + candidates_.size() - 1) % candidates_.size(); }

bool ImeSession::is_incomplete_combination_candidate(const std::string &value) const {
    if (exact_registered_texts_.find(value) != exact_registered_texts_.end()) return false;
    if (incomplete_combination_texts_.find(value) != incomplete_combination_texts_.end()) return true;
    int matched_values = 0;
    for (const auto &registered : blocked_combination_values_) {
        if (value.find(registered) != std::string::npos && ++matched_values >= 2) return true;
    }
    return false;
}

void ImeSession::insert_zenzai_candidate(std::string value) {
    if (value.empty()) return;
    if (is_incomplete_combination_candidate(value)) return;
    if (is_single_hiragana_kana(reading_)) return;
    const auto learned = learning_.find(learning_key());
    const bool strong_learning = learned != learning_.end() &&
        std::any_of(learned->second.begin(), learned->second.end(), [](const auto &entry) {
            return entry.second >= 4;
        });
    const bool exact_registration = std::any_of(user_dictionary_.begin(), user_dictionary_.end(),
        [this](const auto &entry) { return entry.reading == reading_; });
    if (utf8_character_count(reading_) <= 2 && !candidates_.empty() &&
        candidates_.front().text == reading_ &&
        !strong_learning && !exact_registration) return;
    const auto existing = std::find_if(candidates_.begin(), candidates_.end(), [&value](const Candidate &candidate) {
        return candidate.text == value;
    });
    // Reject malformed or unusual new model text; explicit dictionary entries stay available.
    if (existing == candidates_.end() && unusual_model_text(value, reading_)) return;
    if (existing != candidates_.end() && existing->source.find("prediction") != std::string::npos) {
        // A model result cannot make an unfinished dictionary or learned reading live.
        return;
    }
    const bool novel = existing == candidates_.end();
    const bool ordinary_spelling_first = !candidates_.empty() &&
        !strong_learning && !exact_registration && value != candidates_.front().text &&
        ((candidates_.front().text == reading_ && candidates_.front().source == "azookey") ||
         (reading_ == "ないか" && candidates_.front().text == "無いか") ||
         (candidates_.front().text == hiragana_to_katakana(reading_) &&
          (mixes_hiragana_and_katakana(value) ||
           std::any_of(value.begin(), value.end(), [](unsigned char character) {
               return character >= 'A' && character <= 'Z';
           }))));
    const bool preserve_selection = converting_ || selected_index_ != 0;
    const auto selected = selected_text();
    candidates_.erase(std::remove_if(candidates_.begin(), candidates_.end(), [&value](const Candidate &candidate) {
        return candidate.text == value;
    }), candidates_.end());
    const auto insertion_index = novel ? std::min<std::size_t>(3, candidates_.size()) :
        ordinary_spelling_first ? std::min<std::size_t>(1, candidates_.size()) : 0;
    candidates_.insert(candidates_.begin() + static_cast<std::ptrdiff_t>(insertion_index),
        {std::move(value), novel || ordinary_spelling_first ? "zenzai-suggestion" : "zenzai"});
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
    incomplete_combination_texts_.clear();
    normalized_incomplete_combination_texts_.clear();
    exact_registered_texts_.clear();
    blocked_combination_values_.clear();
    allow_trusted_complete_combination_ = false;
    const auto append_converted = [&](std::string text, const char *source) {
        // Keep full lattice paths through ordinary words, while rejecting the
        // literal kana variants of an incomplete registered combination.
        if (std::strcmp(source, "azookey") == 0 && allow_trusted_complete_combination_) {
            if (normalized_incomplete_combination_texts_.find(convert_kana(text, false)) !=
                normalized_incomplete_combination_texts_.end() &&
                exact_registered_texts_.find(text) == exact_registered_texts_.end()) return;
        } else if (is_incomplete_combination_candidate(text)) return;
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
    std::vector<std::string> learned_exact;
    std::vector<DictionaryEntry> learned_combination_entries;
    for (const auto &[ruby, scores] : learning_) {
        if (ruby.rfind("english:", 0) == 0 || conversion_reading.empty()) continue;
        if (conversion_reading.find(ruby) != std::string::npos) {
            for (const auto &[word, score] : scores) {
                if (score > 0 && !word.empty()) {
                    learned_combination_entries.push_back({ruby, word,
                        std::clamp(3 + score / 16, 1, 5)});
                }
            }
        }
        if (ruby == reading_) {
            for (const auto &[word, score] : scores) {
                if (score > 0) learned_exact.push_back(word);
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

    struct SharedPrediction {
        std::string text;
        int importance;
        std::size_t remaining;
        std::string source;
    };
    std::vector<SharedPrediction> shared_predictions;
    std::vector<Candidate> deferred_conversions;
    for (const auto &entry : user_dictionary_) {
        if (entry.reading == conversion_reading) {
            deferred_conversions.push_back({entry.value, entry.source});
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
    const auto registered_combinations = dictionary_combinations(
        conversion_reading, user_dictionary_, 32);
    for (std::size_t i = 0; i < std::min<std::size_t>(8, registered_combinations.size()); ++i) {
        deferred_conversions.push_back({registered_combinations[i], "dictionary-combination"});
    }
    std::vector<DictionaryEntry> all_combination_entries = user_dictionary_;
    all_combination_entries.insert(all_combination_entries.end(),
        learned_combination_entries.begin(), learned_combination_entries.end());
    allow_trusted_complete_combination_ = has_long_ordinary_gap_between_registered_words(
        conversion_reading, all_combination_entries);
    if (dictionary_combinations(conversion_reading, all_combination_entries, 1, true, 2).empty()) {
        std::unordered_set<std::string> seen_values;
        for (const auto &entry : all_combination_entries) {
            if (!entry.reading.empty() && !entry.value.empty() &&
                conversion_reading.find(entry.reading) != std::string::npos &&
                seen_values.insert(entry.value).second) {
                blocked_combination_values_.push_back(entry.value);
            }
        }
    }
    const auto all_combinations = dictionary_combinations(
        conversion_reading, all_combination_entries, 128, false);
    const auto exact_combinations = dictionary_combinations(
        conversion_reading, all_combination_entries, 128);
    const std::unordered_set<std::string> exact_combination_texts(
        exact_combinations.begin(), exact_combinations.end());
    for (const auto &value : all_combinations) {
        if (exact_combination_texts.find(value) == exact_combination_texts.end()) {
            incomplete_combination_texts_.insert(value);
            normalized_incomplete_combination_texts_.insert(convert_kana(value, false));
        }
    }
    for (const auto &entry : user_dictionary_) {
        if (entry.reading == conversion_reading) exact_registered_texts_.insert(entry.value);
    }
    exact_registered_texts_.insert(learned_exact.begin(), learned_exact.end());
    std::unordered_set<std::string> registered_texts(
        registered_combinations.begin(), registered_combinations.end());
    std::unordered_set<std::string> learned_combination_seen;
    std::size_t learned_combination_count = 0;
    const auto add_learned_combinations = [&](const std::vector<std::string> &values) {
        for (const auto &value : values) {
            if (registered_texts.find(value) != registered_texts.end() ||
                !learned_combination_seen.insert(value).second) continue;
            deferred_conversions.push_back({value, "learned-combination"});
            if (++learned_combination_count >= 8) break;
        }
    };
    add_learned_combinations(dictionary_combinations(
        conversion_reading, learned_combination_entries));
    if (learned_combination_count < 8) {
        add_learned_combinations(dictionary_combinations(
            conversion_reading, all_combination_entries, 32));
    }
    for (const auto &entry : learned_predictions) {
        append_unique(prefix_predictions, prediction_seen, entry.text, "learned-prediction");
    }
    if (bundled_dictionary_ && !conversion_reading.empty()) {
        std::vector<AzooKeyAdditionalEntry> additional_entries;
        for (const auto &entry : user_dictionary_) {
            if (entry.reading.empty() || entry.value.empty() ||
                (conversion_reading.find(entry.reading) == std::string::npos &&
                 entry.reading.rfind(conversion_reading, 0) != 0)) continue;
            const auto weight = entry.has_word_weight ? entry.word_weight :
                static_cast<float>((entry.importance - 3) * 2 - 9);
            additional_entries.push_back({entry.value, entry.reading, entry.lcid,
                                          entry.rcid, weight});
        }
        for (const auto &entry : learned_combination_entries) {
            const auto found = learning_.find(entry.reading);
            if (found == learning_.end()) continue;
            const auto score = found->second.find(entry.value);
            // Automatically accepted text is only weak evidence. It stays
            // visible as a learned candidate without changing lattice paths.
            if (score == found->second.end() || score->second < 4) continue;
            const auto count = std::clamp(score->second * 8, 0, 255);
            const auto fraction = 1.0 - static_cast<double>(count) / 255.0;
            const auto length = std::max<std::size_t>(1, utf8_character_count(entry.reading));
            const auto weight = static_cast<float>(-1.0 - 4.0 / length -
                                                   3.0 * std::pow(fraction, 3));
            additional_entries.push_back({entry.value, entry.reading, 1285, 1285, weight});
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
    for (const auto &entry : deferred_conversions) {
        append_converted(entry.text, entry.source.c_str());
    }
    for (const auto &word : learned_exact) {
        append_unique(candidates_, seen, word, "learned");
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
    append_unique(candidates_, seen,
        hiragana_to_katakana(conversion_reading) + literal_suffix, "katakana");
    append_unique(candidates_, seen, raw_input_, "latin");
    auto insertion = candidates_.begin() +
        static_cast<std::ptrdiff_t>(std::min<std::size_t>(1, candidates_.size()));
    std::size_t promoted = 0;
    for (auto &prediction : prefix_predictions) {
        if (promoted >= 4) break;
        const bool prominent = prediction.source == "personal-prediction" ||
            prediction.source == "shared-prediction" ||
            prediction.source == "learned-prediction";
        if (!prominent || !seen.insert(prediction.text).second) continue;
        insertion = candidates_.insert(insertion, std::move(prediction)) + 1;
        ++promoted;
    }
    const auto insertion_index = std::min(candidates_.size(),
        std::max<std::size_t>(2, std::min<std::size_t>(3, conversion_count)) + promoted);
    insertion = candidates_.begin() + static_cast<std::ptrdiff_t>(insertion_index);
    std::size_t inserted = promoted;
    for (auto &prediction : prefix_predictions) {
        if (prediction.text.empty()) continue;
        if (!seen.insert(prediction.text).second) continue;
        insertion = candidates_.insert(insertion, std::move(prediction)) + 1;
        if (++inserted >= 32) break;
    }
    prioritize_learning();
}

}  // namespace keynako
