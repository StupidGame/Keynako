#pragma once

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <string>

namespace keynako {

inline std::filesystem::path official_dictionary_cache(const std::filesystem::path &cache) {
    for (const char *marker : {"current", "previous"}) {
        std::ifstream file(cache / marker);
        std::string sha;
        std::getline(file, sha);
        if (sha.size() != 40 || !std::all_of(sha.begin(), sha.end(), [](char c) {
            return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
        })) continue;
        const auto root = cache / sha / "Dictionary";
        std::error_code error;
        if (std::filesystem::is_regular_file(root / "louds" / "charID.chid", error) && !error) return root;
    }
    return {};
}

}  // namespace keynako
