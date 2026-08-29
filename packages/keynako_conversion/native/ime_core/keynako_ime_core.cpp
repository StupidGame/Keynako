#include "keynako_ime_core.h"

#include <algorithm>
#include <cctype>
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

}  // namespace

void ImeSession::set_mode(InputMode mode) { if (mode_ != mode) { mode_ = mode; clear(); } }
void ImeSession::set_live_conversion(bool enabled) { live_conversion_ = enabled; }
void ImeSession::append_ascii(char value) { raw_input_.push_back(value); rebuild_candidates(); }
void ImeSession::backspace() { if (!raw_input_.empty()) { raw_input_.pop_back(); rebuild_candidates(); } }
void ImeSession::clear() { raw_input_.clear(); reading_.clear(); candidates_.clear(); selected_index_ = 0; }
std::string ImeSession::display_text() const { return live_conversion_ && !candidates_.empty() ? candidates_[selected_index_].text : reading_; }
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
    candidates_.clear(); selected_index_ = 0;
    if (raw_input_.empty()) { reading_.clear(); return; }
    std::unordered_set<std::string> seen;
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
    reading_ = roman_to_hiragana(raw_input_);
    const auto dictionary = kDictionary.find(reading_);
    if (dictionary != kDictionary.end()) for (const auto &value : dictionary->second) append_unique(candidates_, seen, value, "dictionary");
    append_unique(candidates_, seen, reading_, "reading");
    append_unique(candidates_, seen, hiragana_to_katakana(reading_), "katakana");
    append_unique(candidates_, seen, raw_input_, "latin");
}

}  // namespace keynako
