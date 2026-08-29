#!/bin/bash
set -euo pipefail
source_bundle="${1:-$(cd "$(dirname "$0")" && pwd)/Keynako.inputmethod}"
target_root="$HOME/Library/Input Methods"
mkdir -p "$target_root"
rm -rf "$target_root/Keynako.inputmethod"
cp -R "$source_bundle" "$target_root/Keynako.inputmethod"
killall cfprefsd 2>/dev/null || true
echo 'Keynako was installed. Log out and back in, then add it in Keyboard > Input Sources.'
