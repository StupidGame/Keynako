#!/bin/bash
set -euo pipefail
source_bundle="${1:-$(cd "$(dirname "$0")" && pwd)/Keynako.inputmethod}"
target_root="$HOME/Library/Input Methods"
source_app="$(cd "$(dirname "$source_bundle")" && pwd)/Keynako.app"
target_app="$HOME/Applications/Keynako.app"
mkdir -p "$target_root"
rm -rf "$target_root/Keynako.inputmethod"
cp -R "$source_bundle" "$target_root/Keynako.inputmethod"
if [[ -d "$source_app" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$target_app"
  cp -R "$source_app" "$target_app"
fi
killall cfprefsd 2>/dev/null || true
echo 'Keynako was installed. Log out and back in, then add it in Keyboard > Input Sources.'
