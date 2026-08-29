#!/bin/bash
set -euo pipefail
install_root="${XDG_DATA_HOME:-$HOME/.local/share}/keynako"
component="${XDG_DATA_HOME:-$HOME/.local/share}/ibus/component/keynako.xml"
rm -f "$component"
rm -rf "$install_root"
ibus restart 2>/dev/null || true
echo 'Keynako was removed from IBus.'
