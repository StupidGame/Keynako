#!/bin/bash
set -euo pipefail
source_root="${1:-$(cd "$(dirname "$0")" && pwd)}"
install_root="${XDG_DATA_HOME:-$HOME/.local/share}/keynako"
component_root="${XDG_DATA_HOME:-$HOME/.local/share}/ibus/component"
mkdir -p "$install_root" "$component_root"
cp -R "$source_root/." "$install_root/"
if [[ ! -f "$install_root/shared_dictionary.tsv" && -f "$source_root/bundled_shared_dictionary.tsv" ]]; then
  cp "$source_root/bundled_shared_dictionary.tsv" "$install_root/shared_dictionary.tsv"
fi
chmod +x "$install_root/keynako_engine.py" "$install_root/keynako_zenzai" 2>/dev/null || true
sed -e "s|@EXECUTABLE@|$install_root/keynako_engine.py|g" \
    -e "s|@SETUP@|$install_root/keynako_desktop|g" \
    -e "s|@ICON@|$install_root/keynako.png|g" \
    "$source_root/keynako.xml.in" > "$component_root/keynako.xml"
ibus restart 2>/dev/null || true
echo 'Keynako was installed. Add it from your desktop input-source settings.'
