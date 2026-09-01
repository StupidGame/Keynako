#!/bin/bash
set -euo pipefail
target="$HOME/Library/Input Methods/Keynako.inputmethod"
if [[ -d "$target" ]]; then rm -rf "$target"; fi
app="$HOME/Applications/Keynako.app"
if [[ -d "$app" ]]; then rm -rf "$app"; fi
cache="$HOME/Library/Application Support/Keynako/shared_dictionary.tsv"
rm -f "$cache"
rmdir "$(dirname "$cache")" 2>/dev/null || true
killall cfprefsd 2>/dev/null || true
echo 'Keynako was removed. Log out and back in to refresh Input Sources.'
