#pragma once

#include <algorithm>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "keynako_ime_core.h"

namespace keynako {

// An empty vector is a valid cache: it removes entries from a disabled
// dictionary. An invalid or incomplete header leaves the current cache alone.
inline std::optional<std::vector<DictionaryEntry>> load_shared_dictionary_cache(
    const std::filesystem::path &path) {
    std::ifstream stream(path, std::ios::binary);
    if (!stream) return std::nullopt;

    std::vector<DictionaryEntry> entries;
    std::string line;
    bool valid_header = false;
    while (std::getline(stream, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (!valid_header) {
            if (line.rfind("# keynako-shared-dictionary-v1\t", 0) != 0 ||
                std::count(line.begin(), line.end(), '\t') < 3) return std::nullopt;
            valid_header = true;
            continue;
        }
        if (line.empty() || line.front() == '#') continue;
        const auto first_tab = line.find('\t');
        const auto second_tab = first_tab == std::string::npos
            ? std::string::npos
            : line.find('\t', first_tab + 1);
        if (first_tab == std::string::npos || second_tab == std::string::npos) continue;
        try {
            const int importance = std::clamp(std::stoi(line.substr(0, first_tab)), 1, 5);
            std::string reading = line.substr(first_tab + 1, second_tab - first_tab - 1);
            const auto third_tab = line.find('\t', second_tab + 1);
            std::string value = third_tab == std::string::npos
                ? line.substr(second_tab + 1)
                : line.substr(second_tab + 1, third_tab - second_tab - 1);
            if (reading.empty() || value.empty()) continue;
            DictionaryEntry entry{std::move(reading), std::move(value), importance};
            if (third_tab != std::string::npos) {
                const auto fourth_tab = line.find('\t', third_tab + 1);
                const auto fifth_tab = fourth_tab == std::string::npos
                    ? std::string::npos
                    : line.find('\t', fourth_tab + 1);
                if (fourth_tab != std::string::npos && fifth_tab != std::string::npos) {
                    entry.word_weight = std::stof(line.substr(third_tab + 1, fourth_tab - third_tab - 1));
                    entry.lcid = std::stoi(line.substr(fourth_tab + 1, fifth_tab - fourth_tab - 1));
                    entry.rcid = std::stoi(line.substr(fifth_tab + 1));
                    entry.has_word_weight = true;
                }
            }
            entries.push_back(std::move(entry));
        } catch (const std::exception &) {
            continue;
        }
    }
    if (!valid_header || stream.bad()) return std::nullopt;
    return entries;
}

inline std::optional<std::vector<DictionaryEntry>> load_combined_dictionary_caches(
    const std::filesystem::path &shared_path,
    const std::filesystem::path &personal_path) {
    auto shared = load_shared_dictionary_cache(shared_path);
    if (!shared) return std::nullopt;
    std::error_code error;
    const bool personal_exists = std::filesystem::exists(personal_path, error);
    if (error) return shared;
    if (personal_exists) {
        auto personal = load_shared_dictionary_cache(personal_path);
        if (!personal) return shared;
        personal->insert(personal->end(),
                         std::make_move_iterator(shared->begin()),
                         std::make_move_iterator(shared->end()));
        return personal;
    }
    return shared;
}

}  // namespace keynako
