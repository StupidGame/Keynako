#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
output_root="${1:-$repo_root/build/macos-ime}"
bundle="$output_root/Keynako.inputmethod"
core="$repo_root/packages/keynako_conversion/native/ime_core"

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$repo_root/platforms/macos/Info.plist" "$bundle/Contents/Info.plist"

xcrun clang++ -std=c++17 -fobjc-arc -O2 \
  -framework Cocoa -framework InputMethodKit \
  -I "$core" \
  "$repo_root/platforms/macos/KeynakoInputMethod.mm" \
  "$core/keynako_ime_core.cpp" "$core/zenzai_client.cpp" \
  -o "$bundle/Contents/MacOS/KeynakoInputMethod"

codesign --force --deep --sign - "$bundle"
echo "$bundle"
