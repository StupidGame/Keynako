#!/bin/bash
set -euo pipefail
target="$HOME/Library/Input Methods/Keynako.inputmethod"
if [[ -d "$target" ]]; then rm -rf "$target"; fi
killall cfprefsd 2>/dev/null || true
echo 'Keynako was removed. Log out and back in to refresh Input Sources.'
