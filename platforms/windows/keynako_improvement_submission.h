#pragma once

#include <cstddef>
#include <string>

namespace keynako::windows {

struct ImprovementSubmission {
    std::string word;
    std::string reading;
    std::size_t selected_index = 0;
};

std::string build_improvement_payload(const ImprovementSubmission &submission,
                                      const std::string &app_version);

bool submit_improvement_https(const std::wstring &endpoint,
                              const std::string &payload);

}  // namespace keynako::windows
