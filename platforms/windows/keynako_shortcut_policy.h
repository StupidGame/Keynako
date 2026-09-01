#pragma once

#include <cstdint>

namespace keynako::windows {

// Virtual-key values are part of the stable Win32 ABI. Keeping the policy
// independent from windows.h makes the JIS/US routing easy to unit test.
constexpr std::uint32_t kKeyKanji = 0x19;
constexpr std::uint32_t kKeyConvert = 0x1c;
constexpr std::uint32_t kKeySpace = 0x20;
constexpr std::uint32_t kKeyOemGrave = 0xc0;
constexpr std::uint32_t kScanCodeJisHankakuZenkaku = 0x29;
constexpr std::uint32_t kScanCodeJisConvert = 0x79;

constexpr bool is_convert_key(std::uint32_t key, std::uint32_t scan_code) {
    return key == kKeyConvert || scan_code == kScanCodeJisConvert;
}

constexpr bool is_hankaku_zenkaku_key(std::uint32_t key,
                                      std::uint32_t scan_code,
                                      bool japanese_keyboard) {
    return key == kKeyKanji ||
           (japanese_keyboard &&
            scan_code == kScanCodeJisHankakuZenkaku);
}

enum class ShortcutAction {
    none,
    toggle_input_mode,
    convert_or_cycle,
};

constexpr ShortcutAction shortcut_action(std::uint32_t key,
                                          std::uint32_t scan_code,
                                          bool control, bool alt,
                                          bool has_composition,
                                          bool japanese_keyboard = false) {
    if (control && !alt && key == kKeySpace) {
        return ShortcutAction::toggle_input_mode;
    }
    if (alt && !control && key == kKeyOemGrave) {
        return ShortcutAction::toggle_input_mode;
    }
    if (control || alt) return ShortcutAction::none;
    if (is_hankaku_zenkaku_key(key, scan_code, japanese_keyboard)) {
        return ShortcutAction::toggle_input_mode;
    }
    // Convert mirrors Space conversion. With no composition it is left to the
    // application instead of being repurposed as an input-mode toggle.
    if (is_convert_key(key, scan_code) && has_composition) {
        return ShortcutAction::convert_or_cycle;
    }
    return ShortcutAction::none;
}

}  // namespace keynako::windows
