#pragma once

#include <cstddef>
#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace keynako {

struct AzooKeyAdditionalEntry {
    std::string word;
    std::string ruby;
    int lcid = 1285;
    int rcid = 1285;
    float score = -17.0f;
};

// Reads the LOUDS dictionary shipped by azooKey_dictionary_storage and applies
// the same word/connection score beam search used by the Android implementation.
class AzooKeyDictionary {
public:
    explicit AzooKeyDictionary(std::filesystem::path root);
    ~AzooKeyDictionary();

    AzooKeyDictionary(AzooKeyDictionary &&) noexcept;
    AzooKeyDictionary &operator=(AzooKeyDictionary &&) noexcept;
    AzooKeyDictionary(const AzooKeyDictionary &) = delete;
    AzooKeyDictionary &operator=(const AzooKeyDictionary &) = delete;

    bool available() const;
    std::vector<std::string> candidates(const std::string &hiragana_reading,
                                        std::size_t limit = 48,
                                        const std::vector<AzooKeyAdditionalEntry> &additional_entries = {});

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

}  // namespace keynako
