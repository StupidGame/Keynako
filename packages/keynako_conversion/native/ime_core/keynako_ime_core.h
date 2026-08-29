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

    const std::string &raw_input() const { return raw_input_; }
    const std::string &reading() const { return reading_; }
    const std::vector<Candidate> &candidates() const { return candidates_; }
    std::size_t selected_index() const { return selected_index_; }
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
    std::string raw_input_;
    std::string reading_;
    std::vector<Candidate> candidates_;
    std::size_t selected_index_ = 0;
};

}  // namespace keynako
