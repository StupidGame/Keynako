#include "azookey_dictionary.h"

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iterator>
#include <limits>
#include <map>
#include <optional>
#include <queue>
#include <sstream>
#include <unordered_map>
#include <unordered_set>
#include <utility>

namespace keynako {
namespace {

constexpr int kRootNode = 1;
constexpr int kBosCid = 0;
constexpr int kGeneralNounCid = 1285;
constexpr int kCidCount = 1319;
constexpr int kShardShift = 11;
constexpr int kLocalMask = (1 << kShardShift) - 1;
constexpr std::size_t kMaxWordLength = 20;
constexpr std::size_t kBeamWidth = 48;
constexpr std::size_t kBeamTrimThreshold = 256;
constexpr std::size_t kEntriesPerReading = 32;
constexpr float kFallbackScore = -17.0f;
constexpr float kDefaultConnectionScore = -25.0f;

std::vector<std::uint8_t> read_bytes(const std::filesystem::path &path) {
    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    if (!stream) return {};
    const std::streamsize length = stream.tellg();
    if (length <= 0) return {};
    std::vector<std::uint8_t> bytes(static_cast<std::size_t>(length));
    stream.seekg(0);
    if (!stream.read(reinterpret_cast<char *>(bytes.data()), length)) return {};
    return bytes;
}

std::uint16_t read_u16(const std::vector<std::uint8_t> &bytes, std::size_t offset) {
    if (offset + 2 > bytes.size()) return 0;
    return static_cast<std::uint16_t>(bytes[offset]) |
           (static_cast<std::uint16_t>(bytes[offset + 1]) << 8);
}

std::uint32_t read_u32(const std::vector<std::uint8_t> &bytes, std::size_t offset) {
    if (offset + 4 > bytes.size()) return 0;
    return static_cast<std::uint32_t>(bytes[offset]) |
           (static_cast<std::uint32_t>(bytes[offset + 1]) << 8) |
           (static_cast<std::uint32_t>(bytes[offset + 2]) << 16) |
           (static_cast<std::uint32_t>(bytes[offset + 3]) << 24);
}

std::uint64_t read_u64(const std::vector<std::uint8_t> &bytes, std::size_t offset) {
    std::uint64_t value = 0;
    if (offset + 8 > bytes.size()) return value;
    for (std::size_t index = 0; index < 8; ++index) {
        value |= static_cast<std::uint64_t>(bytes[offset + index]) << (index * 8);
    }
    return value;
}

std::int32_t read_i32(const std::vector<std::uint8_t> &bytes, std::size_t offset) {
    return static_cast<std::int32_t>(read_u32(bytes, offset));
}

float read_float(const std::vector<std::uint8_t> &bytes, std::size_t offset) {
    const std::uint32_t raw = read_u32(bytes, offset);
    float value = 0;
    static_assert(sizeof(value) == sizeof(raw), "unexpected float size");
    std::memcpy(&value, &raw, sizeof(value));
    return value;
}

std::u32string utf8_to_u32(const std::string &input) {
    std::u32string output;
    for (std::size_t index = 0; index < input.size();) {
        const auto first = static_cast<unsigned char>(input[index]);
        char32_t value = 0xfffd;
        std::size_t length = 1;
        if (first < 0x80) {
            value = first;
        } else if ((first & 0xe0) == 0xc0 && index + 1 < input.size()) {
            value = static_cast<char32_t>(first & 0x1f) << 6;
            value |= static_cast<unsigned char>(input[index + 1]) & 0x3f;
            length = 2;
        } else if ((first & 0xf0) == 0xe0 && index + 2 < input.size()) {
            value = static_cast<char32_t>(first & 0x0f) << 12;
            value |= static_cast<char32_t>(static_cast<unsigned char>(input[index + 1]) & 0x3f) << 6;
            value |= static_cast<unsigned char>(input[index + 2]) & 0x3f;
            length = 3;
        } else if ((first & 0xf8) == 0xf0 && index + 3 < input.size()) {
            value = static_cast<char32_t>(first & 0x07) << 18;
            value |= static_cast<char32_t>(static_cast<unsigned char>(input[index + 1]) & 0x3f) << 12;
            value |= static_cast<char32_t>(static_cast<unsigned char>(input[index + 2]) & 0x3f) << 6;
            value |= static_cast<unsigned char>(input[index + 3]) & 0x3f;
            length = 4;
        }
        output.push_back(value);
        index += length;
    }
    return output;
}

std::string u32_to_utf8(const std::u32string &input) {
    std::string output;
    for (const char32_t value : input) {
        if (value <= 0x7f) {
            output.push_back(static_cast<char>(value));
        } else if (value <= 0x7ff) {
            output.push_back(static_cast<char>(0xc0 | (value >> 6)));
            output.push_back(static_cast<char>(0x80 | (value & 0x3f)));
        } else if (value <= 0xffff) {
            output.push_back(static_cast<char>(0xe0 | (value >> 12)));
            output.push_back(static_cast<char>(0x80 | ((value >> 6) & 0x3f)));
            output.push_back(static_cast<char>(0x80 | (value & 0x3f)));
        } else {
            output.push_back(static_cast<char>(0xf0 | (value >> 18)));
            output.push_back(static_cast<char>(0x80 | ((value >> 12) & 0x3f)));
            output.push_back(static_cast<char>(0x80 | ((value >> 6) & 0x3f)));
            output.push_back(static_cast<char>(0x80 | (value & 0x3f)));
        }
    }
    return output;
}

std::u32string to_katakana(std::u32string value) {
    for (auto &character : value) {
        if (character >= 0x3041 && character <= 0x3096) character += 0x60;
    }
    return value;
}

std::string to_hiragana(char32_t character) {
    if (character >= 0x30a1 && character <= 0x30f6) character -= 0x60;
    return u32_to_utf8(std::u32string(1, character));
}

std::string escaped_identifier(char32_t character) {
    std::ostringstream output;
    output << '[' << std::uppercase << std::hex << std::setw(4) << std::setfill('0')
           << static_cast<std::uint32_t>(character) << ']';
    return output.str();
}

struct Entry {
    std::string word;
    std::string ruby;
    int lcid = 0;
    int rcid = 0;
    float score = 0;
};

struct BeamPath {
    std::string text;
    float score = 0;
    int last_rcid = 0;
};

struct ConnectionLine {
    float default_score = kDefaultConnectionScore;
    std::unordered_map<int, float> overrides;
};

std::vector<std::string> split_tab_fields(const std::vector<std::uint8_t> &bytes,
                                          std::size_t start, std::size_t end) {
    std::vector<std::string> fields;
    std::size_t field_start = start;
    for (std::size_t index = start; index <= end; ++index) {
        if (index == end || bytes[index] == '\t') {
            fields.emplace_back(reinterpret_cast<const char *>(bytes.data() + field_start), index - field_start);
            field_start = index + 1;
        }
    }
    return fields;
}

class LoudsShard {
public:
    LoudsShard(std::filesystem::path dictionary_root, std::string identifier,
               std::vector<std::uint8_t> louds, std::vector<std::uint8_t> node_characters,
               const std::unordered_map<char32_t, int> *character_ids)
        : dictionary_root_(std::move(dictionary_root)), identifier_(std::move(identifier)),
          node_characters_(std::move(node_characters)), character_ids_(character_ids),
          child_starts_(node_characters_.size()), child_ends_(node_characters_.size()) {
        decode_child_ranges(louds);
    }

    std::vector<std::pair<std::size_t, std::vector<Entry>>> matching_entries(
        const std::u32string &text, std::size_t start, std::size_t max_length) {
        int node = kRootNode;
        std::vector<std::pair<std::size_t, std::vector<Entry>>> result;
        const auto end = std::min(text.size(), start + max_length);
        for (std::size_t index = start; index < end; ++index) {
            const auto character = character_ids_->find(text[index]);
            if (character == character_ids_->end()) break;
            const auto next = child(node, character->second);
            if (!next) break;
            node = *next;
            auto values = entries(node);
            if (!values.empty()) result.emplace_back(index + 1, std::move(values));
        }
        return result;
    }

private:
    std::optional<int> child(int parent, int character_id) const {
        if (parent < 0 || static_cast<std::size_t>(parent) >= child_starts_.size()) return std::nullopt;
        for (int index = child_starts_[parent]; index < child_ends_[parent]; ++index) {
            if (index >= 0 && static_cast<std::size_t>(index) < node_characters_.size() &&
                node_characters_[index] == static_cast<std::uint8_t>(character_id)) {
                return index;
            }
        }
        return std::nullopt;
    }

    std::vector<Entry> entries(int node) {
        const auto cached = entries_by_node_.find(node);
        if (cached != entries_by_node_.end()) return cached->second;
        const int shard_index = node >> kShardShift;
        const auto shard = data_shards_.find(shard_index);
        if (shard == data_shards_.end()) {
            const auto path = dictionary_root_ / "louds" /
                (identifier_ + std::to_string(shard_index) + ".loudstxt3");
            data_shards_[shard_index] = read_bytes(path);
        }
        const auto &bytes = data_shards_[shard_index];
        auto parsed = parse_entries(bytes, node & kLocalMask);
        entries_by_node_.emplace(node, parsed);
        return parsed;
    }

    static std::vector<Entry> parse_entries(const std::vector<std::uint8_t> &bytes,
                                            int local_index) {
        if (bytes.size() < 6) return {};
        const auto slot_count = read_u16(bytes, 0);
        if (local_index < 0 || local_index >= slot_count ||
            bytes.size() < 2 + static_cast<std::size_t>(slot_count) * 4) return {};
        const auto start = static_cast<std::size_t>(read_u32(bytes, 2 + local_index * 4));
        const auto end = local_index == slot_count - 1
            ? bytes.size()
            : static_cast<std::size_t>(read_u32(bytes, 2 + (local_index + 1) * 4));
        if (start + 2 > end || end > bytes.size()) return {};
        const auto count = read_u16(bytes, start);
        std::size_t position = start + 2;
        if (count == 0 || position + static_cast<std::size_t>(count) * 10 > end) return {};
        struct Numeric { int lcid; int rcid; float score; };
        std::vector<Numeric> numeric;
        numeric.reserve(count);
        for (std::size_t index = 0; index < count; ++index) {
            numeric.push_back({read_u16(bytes, position), read_u16(bytes, position + 2),
                               read_float(bytes, position + 6)});
            position += 10;
        }
        const auto fields = split_tab_fields(bytes, position, end);
        if (fields.empty() || fields.front().empty()) return {};
        std::vector<Entry> result;
        result.reserve(count);
        for (std::size_t index = 0; index < count; ++index) {
            std::string word = index + 1 < fields.size() ? fields[index + 1] : "";
            if (word.empty()) word = fields.front();
            result.push_back({std::move(word), fields.front(), numeric[index].lcid,
                              numeric[index].rcid, numeric[index].score});
        }
        return result;
    }

    void decode_child_ranges(const std::vector<std::uint8_t> &bytes) {
        int ones = 0;
        std::size_t zeros = 0;
        int segment_start = 1;
        for (std::size_t offset = 0; offset + 8 <= bytes.size() && zeros < node_characters_.size(); offset += 8) {
            const auto word = read_u64(bytes, offset);
            for (int shift = 63; shift >= 0; --shift) {
                if (((word >> shift) & 1u) != 0) {
                    ++ones;
                } else {
                    child_starts_[zeros] = segment_start;
                    child_ends_[zeros] = ones + 1;
                    ++zeros;
                    segment_start = ones + 1;
                    if (zeros >= node_characters_.size()) return;
                }
            }
        }
    }

    std::filesystem::path dictionary_root_;
    std::string identifier_;
    std::vector<std::uint8_t> node_characters_;
    const std::unordered_map<char32_t, int> *character_ids_;
    std::vector<int> child_starts_;
    std::vector<int> child_ends_;
    std::unordered_map<int, std::vector<Entry>> entries_by_node_;
    std::unordered_map<int, std::vector<std::uint8_t>> data_shards_;
};

}  // namespace

struct AzooKeyDictionary::Impl {
    explicit Impl(std::filesystem::path value) : root(std::move(value)) {
        const auto bytes = read_bytes(root / "louds" / "charID.chid");
        if (bytes.empty()) return;
        const std::string encoded(reinterpret_cast<const char *>(bytes.data()), bytes.size());
        const auto characters = utf8_to_u32(encoded);
        for (std::size_t index = 0; index < characters.size(); ++index) {
            character_ids[characters[index]] = static_cast<int>(index);
        }
        ready = !character_ids.empty();
    }

    LoudsShard *shard(char32_t first) {
        const auto found = shards.find(first);
        if (found != shards.end()) return found->second.get();
        const auto identifier = escaped_identifier(first);
        auto louds = read_bytes(root / "louds" / (identifier + ".louds"));
        auto characters = read_bytes(root / "louds" / (identifier + ".loudschars2"));
        if (louds.empty() || characters.empty()) {
            shards.emplace(first, nullptr);
            return nullptr;
        }
        auto value = std::make_unique<LoudsShard>(root, identifier, std::move(louds),
                                                  std::move(characters), &character_ids);
        auto *result = value.get();
        shards.emplace(first, std::move(value));
        return result;
    }

    float connection_score(int former, int latter) {
        if (former < 0 || former >= kCidCount || latter < 0 || latter >= kCidCount) {
            return kDefaultConnectionScore;
        }
        auto found = connection_lines.find(former);
        if (found == connection_lines.end()) {
            ConnectionLine line;
            const auto bytes = read_bytes(root / "cb" / (std::to_string(former) + ".binary"));
            for (std::size_t offset = 0; offset + 8 <= bytes.size(); offset += 8) {
                const int key = read_i32(bytes, offset);
                const float value = read_float(bytes, offset + 4);
                if (key == -1) line.default_score = value;
                else if (key >= 0 && key < kCidCount) line.overrides[key] = value;
            }
            found = connection_lines.emplace(former, std::move(line)).first;
        }
        const auto override = found->second.overrides.find(latter);
        return override == found->second.overrides.end()
            ? found->second.default_score
            : override->second;
    }

    void append_paths(std::vector<BeamPath> &destination,
                      const std::vector<BeamPath> &previous,
                      const std::vector<Entry> &entries) {
        for (const auto &entry : entries) {
            for (const auto &path : previous) {
                destination.push_back({path.text + entry.word,
                    path.score + entry.score + connection_score(path.last_rcid, entry.lcid),
                    entry.rcid});
            }
        }
        if (destination.size() <= kBeamTrimThreshold) return;
        std::stable_sort(destination.begin(), destination.end(),
            [](const BeamPath &left, const BeamPath &right) { return left.score > right.score; });
        std::unordered_set<std::string> seen;
        std::vector<BeamPath> trimmed;
        for (auto &path : destination) {
            const auto key = path.text + '\0' + std::to_string(path.last_rcid);
            if (seen.insert(key).second) trimmed.push_back(std::move(path));
            if (trimmed.size() >= kBeamWidth) break;
        }
        destination = std::move(trimmed);
    }

    std::filesystem::path root;
    bool ready = false;
    std::unordered_map<char32_t, int> character_ids;
    std::unordered_map<char32_t, std::unique_ptr<LoudsShard>> shards;
    std::unordered_map<int, ConnectionLine> connection_lines;
};

AzooKeyDictionary::AzooKeyDictionary(std::filesystem::path root)
    : impl_(std::make_unique<Impl>(std::move(root))) {}
AzooKeyDictionary::~AzooKeyDictionary() = default;
AzooKeyDictionary::AzooKeyDictionary(AzooKeyDictionary &&) noexcept = default;
AzooKeyDictionary &AzooKeyDictionary::operator=(AzooKeyDictionary &&) noexcept = default;

bool AzooKeyDictionary::available() const { return impl_ && impl_->ready; }

std::vector<std::string> AzooKeyDictionary::candidates(const std::string &hiragana_reading,
                                                       std::size_t limit,
                                                       const std::vector<AzooKeyAdditionalEntry> &additional_entries) {
    if (!available() || hiragana_reading.empty() || limit == 0) return {};
    const auto reading = to_katakana(utf8_to_u32(hiragana_reading));
    if (reading.empty()) return {};
    struct DynamicEntry {
        std::u32string ruby;
        Entry entry;
    };
    std::vector<DynamicEntry> dynamic_entries;
    dynamic_entries.reserve(additional_entries.size());
    for (const auto &value : additional_entries) {
        auto ruby = to_katakana(utf8_to_u32(value.ruby));
        if (ruby.empty() || value.word.empty()) continue;
        dynamic_entries.push_back({std::move(ruby),
            {value.word, value.ruby, value.lcid, value.rcid, value.score}});
    }
    std::vector<std::vector<BeamPath>> beams(reading.size() + 1);
    beams.front().push_back({"", 0, kBosCid});

    for (std::size_t start = 0; start < reading.size(); ++start) {
        auto previous = beams[start];
        std::stable_sort(previous.begin(), previous.end(),
            [](const BeamPath &left, const BeamPath &right) { return left.score > right.score; });
        if (previous.size() > kBeamWidth) previous.resize(kBeamWidth);
        if (previous.empty()) continue;

        std::map<std::size_t, std::vector<Entry>> matches_by_end;
        if (auto *dictionary_shard = impl_->shard(reading[start])) {
            for (auto &[end, entries] :
                 dictionary_shard->matching_entries(reading, start, kMaxWordLength)) {
                auto &destination = matches_by_end[end];
                destination.insert(destination.end(),
                                   std::make_move_iterator(entries.begin()),
                                   std::make_move_iterator(entries.end()));
            }
        }
        for (const auto &dynamic : dynamic_entries) {
            const auto end = start + dynamic.ruby.size();
            if (end <= reading.size() &&
                std::equal(dynamic.ruby.begin(), dynamic.ruby.end(), reading.begin() + start)) {
                matches_by_end[end].push_back(dynamic.entry);
            }
        }
        bool has_single_character_entry = false;
        for (auto &[end, entries] : matches_by_end) {
            if (end == start + 1 && !entries.empty()) has_single_character_entry = true;
            std::stable_sort(entries.begin(), entries.end(),
                [](const Entry &left, const Entry &right) { return left.score > right.score; });
            if (entries.size() > kEntriesPerReading) entries.resize(kEntriesPerReading);
            impl_->append_paths(beams[end], previous, entries);
        }
        if (!has_single_character_entry) {
            const Entry fallback{to_hiragana(reading[start]), u32_to_utf8({reading[start]}),
                                 kGeneralNounCid, kGeneralNounCid, kFallbackScore};
            impl_->append_paths(beams[start + 1], previous, {fallback});
        }
    }

    std::stable_sort(beams.back().begin(), beams.back().end(),
        [](const BeamPath &left, const BeamPath &right) { return left.score > right.score; });
    std::unordered_set<std::string> seen;
    std::vector<std::string> result;
    for (const auto &path : beams.back()) {
        if (!path.text.empty() && seen.insert(path.text).second) result.push_back(path.text);
        if (result.size() >= limit) break;
    }
    return result;
}

}  // namespace keynako
