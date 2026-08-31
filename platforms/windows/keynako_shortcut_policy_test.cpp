#include "keynako_shortcut_policy.h"

using keynako::windows::ShortcutAction;
using keynako::windows::shortcut_action;

static_assert(shortcut_action(0x1c, false, false, false) ==
              ShortcutAction::toggle_input_mode);
static_assert(shortcut_action(0x1c, false, false, true) ==
              ShortcutAction::convert_or_cycle);
static_assert(shortcut_action(0xc0, false, true, false) ==
              ShortcutAction::toggle_input_mode);
static_assert(shortcut_action(0x20, true, false, false) ==
              ShortcutAction::toggle_input_mode);

int main() {
    // A hardware Convert key keeps its meaning even when the active keyboard
    // layout is US: without composition it toggles, with composition it converts.
    if (shortcut_action(0x1c, false, false, false) !=
        ShortcutAction::toggle_input_mode) return 1;
    if (shortcut_action(0x1c, false, false, true) !=
        ShortcutAction::convert_or_cycle) return 2;

    // Standard US-keyboard alternatives match Microsoft IME behavior.
    if (shortcut_action(0xc0, false, true, false) !=
        ShortcutAction::toggle_input_mode) return 3;
    if (shortcut_action(0x20, true, false, false) !=
        ShortcutAction::toggle_input_mode) return 4;

    if (shortcut_action('A', true, false, false) != ShortcutAction::none) return 5;
    if (shortcut_action(0xc0, true, true, false) != ShortcutAction::none) return 6;
    return 0;
}
