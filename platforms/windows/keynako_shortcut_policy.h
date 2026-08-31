#pragma once

#include <cstdint>

namespace keynako::windows {

// Virtual-key values are part of the stable Win32 ABI. Keeping the policy
// independent from windows.h makes the JIS/US routing easy to unit test.
constexpr std::uint32_t kKeyKanji = 0x19;
constexpr std::uint32_t kKeyConvert = 0x1c;
constexpr std::uint32_t kKeySpace = 0x20;
constexpr std::uint32_t kKeyOemGrave = 0xc0;

enum class ShortcutAction {
    none,
    toggle_input_mode,
    convert_or_cycle,
};

constexpr ShortcutAction shortcut_action(std::uint32_t key, bool control,
                                          bool alt, bool has_composition) {
    if (control && !alt && key == kKeySpace) {
        return ShortcutAction::toggle_input_mode;
    }
    if (alt && !control && key == kKeyOemGrave) {
        return ShortcutAction::toggle_input_mode;
    }
    if (control || alt) return ShortcutAction::none;
    if (key == kKeyKanji) return ShortcutAction::toggle_input_mode;
    if (key == kKeyConvert) {
        return has_composition ? ShortcutAction::convert_or_cycle
                               : ShortcutAction::toggle_input_mode;
    }
    return ShortcutAction::none;
}

}  // namespace keynako::windows
