#pragma once

#include <algorithm>
#include <optional>
#include <string>
#include <utility>

namespace keynako::windows {

enum class PersonalEntryUpdateStatus { added, already_exists, invalid };

struct PersonalEntryUpdate {
    PersonalEntryUpdateStatus status;
    std::string content;
};

inline bool valid_personal_entry_field(const std::string &field) {
    return !field.empty() && field.find_first_of("\t\r\n") == std::string::npos;
}

inline PersonalEntryUpdate prepare_personal_entry_update(
    const std::optional<std::string> &current,
    const std::string &reading,
    const std::string &word) {
    if (!valid_personal_entry_field(reading) ||
        !valid_personal_entry_field(word)) {
        return {PersonalEntryUpdateStatus::invalid, {}};
    }

    std::string content = current.value_or(
        "# keynako-shared-dictionary-v1\tlocal\t1\tmanual\n");
    if (current) {
        const auto header_end = content.find('\n');
        const std::string header = content.substr(0, header_end);
        if (header.rfind("# keynako-shared-dictionary-v1\t", 0) != 0 ||
            std::count(header.begin(), header.end(), '\t') < 3) {
            return {PersonalEntryUpdateStatus::invalid, {}};
        }
        std::size_t start = header_end == std::string::npos
            ? content.size() : header_end + 1;
        while (start < content.size()) {
            const auto end = content.find('\n', start);
            std::string line = content.substr(start, end - start);
            if (!line.empty() && line.back() == '\r') line.pop_back();
            const auto first = line.find('\t');
            const auto second = first == std::string::npos
                ? std::string::npos : line.find('\t', first + 1);
            const auto third = second == std::string::npos
                ? std::string::npos : line.find('\t', second + 1);
            if (second != std::string::npos &&
                line.substr(first + 1, second - first - 1) == reading &&
                line.substr(second + 1, third - second - 1) == word) {
                return {PersonalEntryUpdateStatus::already_exists, std::move(content)};
            }
            if (end == std::string::npos) break;
            start = end + 1;
        }
    }
    if (!content.empty() && content.back() != '\n') content += '\n';
    content += "3\t" + reading + "\t" + word + '\n';
    return {PersonalEntryUpdateStatus::added, std::move(content)};
}

}  // namespace keynako::windows
