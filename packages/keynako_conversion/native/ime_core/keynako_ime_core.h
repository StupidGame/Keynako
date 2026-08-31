#pragma once

#include <cstddef>
#include <string>
#include <vector>

namespace keynako {

enum class InputMode { japanese, english };

struct Candidate {
    std::string text;
    std::string source;
};

struct DictionaryEntry {
    std::string reading;
    std::string value;
    int importance = 3;
};

// Platform-neutral input state. Strings crossing this boundary are UTF-8.
class ImeSession {
public:
    void set_mode(InputMode mode);
    InputMode mode() const { return mode_; }
    void set_live_conversion(bool enabled);
    bool live_conversion() const { return live_conversion_; }
    void append_ascii(char value);
    void backspace();
    void clear();
    bool begin_conversion();
    bool cancel_conversion();
    bool select_candidate(std::size_t index);
    bool select_reading();
    void set_user_dictionary(std::vector<DictionaryEntry> entries);

    const std::string &raw_input() const { return raw_input_; }
    const std::string &reading() const { return reading_; }
    const std::vector<Candidate> &candidates() const { return candidates_; }
    std::size_t selected_index() const { return selected_index_; }
    bool is_converting() const { return converting_; }
    std::string display_text() const;
    std::string selected_text() const;

    void select_next();
    void select_previous();
    void insert_zenzai_candidate(std::string value);
    static std::string roman_to_hiragana(const std::string &input);

private:
    void rebuild_candidates();

    InputMode mode_ = InputMode::japanese;
    bool live_conversion_ = true;
    bool converting_ = false;
    bool live_conversion_suspended_ = false;
    std::string raw_input_;
    std::string reading_;
    std::vector<Candidate> candidates_;
    std::vector<DictionaryEntry> user_dictionary_;
    std::size_t selected_index_ = 0;
};

}  // namespace keynako
