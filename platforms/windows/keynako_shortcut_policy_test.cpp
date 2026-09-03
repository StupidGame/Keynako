#include "keynako_shortcut_policy.h"

using keynako::windows::ShortcutAction;
using keynako::windows::DirectInputMode;
using keynako::windows::direct_input_mode_for_key;
using keynako::windows::is_convert_key;
using keynako::windows::is_candidate_selection_key;
using keynako::windows::is_hankaku_zenkaku_key;
using keynako::windows::is_oem_text_key;
using keynako::windows::is_slash_text_key;
using keynako::windows::oem_text_fallback;
using keynako::windows::shortcut_action;

static_assert(shortcut_action(0x1c, 0, false, false, false) ==
              ShortcutAction::none);
static_assert(shortcut_action(0x1c, 0, false, false, true) ==
              ShortcutAction::convert_or_cycle);
static_assert(shortcut_action(0, 0x79, false, false, false) ==
              ShortcutAction::none);
static_assert(shortcut_action(0, 0x79, false, false, true) ==
              ShortcutAction::convert_or_cycle);
static_assert(is_convert_key(0, 0x79));
static_assert(is_convert_key(0xff, 0x79));
static_assert(is_convert_key(0x1c, 0));
static_assert(is_convert_key(0x1c, 0x79));
static_assert(!is_convert_key(0, 0x7b));
static_assert(is_hankaku_zenkaku_key(0x19, 0, false));
static_assert(is_hankaku_zenkaku_key(0xc0, 0x29, true));
static_assert(!is_hankaku_zenkaku_key(0xc0, 0x29, false));
static_assert(shortcut_action(0xc0, 0x29, false, false, false, true) ==
              ShortcutAction::toggle_input_mode);
static_assert(shortcut_action(0xc0, 0x29, false, false, false, false) ==
              ShortcutAction::none);
static_assert(shortcut_action(0xc0, 0, false, true, false) ==
              ShortcutAction::toggle_input_mode);
static_assert(shortcut_action(0x20, 0, true, false, false) ==
              ShortcutAction::toggle_input_mode);
static_assert(is_oem_text_key(0xbf));
static_assert(oem_text_fallback(0xbf, false) == '/');
static_assert(oem_text_fallback(0xbf, true) == '?');
static_assert(is_slash_text_key(0xff, 0x35));
static_assert(is_oem_text_key(0xff, 0x35));
static_assert(oem_text_fallback(0xff, false, 0x35) == '/');
static_assert(oem_text_fallback(0xff, true, 0x35) == '?');
static_assert(!is_slash_text_key(0x6f, 0x35));
static_assert(direct_input_mode_for_key(0x15) == DirectInputMode::japanese);
static_assert(direct_input_mode_for_key(0x16) == DirectInputMode::japanese);
static_assert(direct_input_mode_for_key(0xf2) == DirectInputMode::japanese);
static_assert(direct_input_mode_for_key(0xf4) == DirectInputMode::japanese);
static_assert(direct_input_mode_for_key(0x1a) == DirectInputMode::english);
static_assert(direct_input_mode_for_key(0xf0) == DirectInputMode::english);
static_assert(direct_input_mode_for_key(0xf3) == DirectInputMode::english);
static_assert(direct_input_mode_for_key(0x19) == DirectInputMode::none);


int main() {
    // Convert mirrors Space conversion on both JIS and US logical layouts. It
    // is not an input-mode toggle when there is no composition.
    if (shortcut_action(0x1c, 0, false, false, false) !=
        ShortcutAction::none) return 1;
    if (shortcut_action(0x1c, 0, false, false, true) !=
        ShortcutAction::convert_or_cycle) return 2;

    // Standard US-keyboard alternatives match Microsoft IME behavior.
    if (shortcut_action(0xc0, 0, false, true, false) !=
        ShortcutAction::toggle_input_mode) return 3;
    if (shortcut_action(0x20, 0, true, false, false) !=
        ShortcutAction::toggle_input_mode) return 4;

    if (shortcut_action(0, 0x79, false, false, false) !=
        ShortcutAction::none) return 5;
    if (!is_convert_key(0xff, 0x79)) return 8;
    if (!is_convert_key(0x1c, 0)) return 9;
    if (shortcut_action(0xc0, 0x29, false, false, false, true) !=
        ShortcutAction::toggle_input_mode) return 10;
    if (shortcut_action(0xc0, 0x29, false, false, false, false) !=
        ShortcutAction::none) return 11;
    if (shortcut_action('A', 0, true, false, false) != ShortcutAction::none) return 6;
    if (shortcut_action(0xc0, 0, true, true, false) != ShortcutAction::none) return 7;
    if (!is_oem_text_key(0xbf)) return 12;
    if (oem_text_fallback(0xbf, false) != '/') return 13;
    if (oem_text_fallback(0xbf, true) != '?') return 14;
    if (!is_oem_text_key(0xff, 0x35)) return 15;
    if (oem_text_fallback(0xff, false, 0x35) != '/') return 16;
    if (oem_text_fallback(0xff, true, 0x35) != '?') return 17;
    if (is_slash_text_key(0x6f, 0x35)) return 18;
    if (direct_input_mode_for_key(0xf3) != DirectInputMode::english) return 19;
    if (direct_input_mode_for_key(0xf4) != DirectInputMode::japanese) return 20;
    if (direct_input_mode_for_key(0x16) != DirectInputMode::japanese) return 21;
    if (direct_input_mode_for_key(0x1a) != DirectInputMode::english) return 22;
    return 0;
}
