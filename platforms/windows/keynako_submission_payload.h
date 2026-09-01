#pragma once

#include <string>

namespace keynako::windows {

inline std::string json_escape(const std::string &value) {
    constexpr char hex[] = "0123456789abcdef";
    std::string escaped;
    escaped.reserve(value.size());
    for (const unsigned char character : value) {
        switch (character) {
            case '"': escaped += "\\\""; break;
            case '\\': escaped += "\\\\"; break;
            case '\b': escaped += "\\b"; break;
            case '\f': escaped += "\\f"; break;
            case '\n': escaped += "\\n"; break;
            case '\r': escaped += "\\r"; break;
            case '\t': escaped += "\\t"; break;
            default:
                if (character < 0x20) {
                    escaped += "\\u00";
                    escaped += hex[(character >> 4) & 0x0f];
                    escaped += hex[character & 0x0f];
                } else {
                    escaped += static_cast<char>(character);
                }
        }
    }
    return escaped;
}

inline std::string shared_candidate_payload(const std::string &word,
                                            const std::string &ruby) {
    return "{\"word\":\"" + json_escape(word) +
           "\",\"ruby\":\"" + json_escape(ruby) +
           "\",\"importance\":3,\"categories\":[],"
           "\"note\":\"Windows candidate right-click\","
           "\"source\":\"Keynako\",\"app_version\":\"3.0.1\"}";
}

}  // namespace keynako::windows
