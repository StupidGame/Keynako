# macOS InputMethodKit adapter

The build script creates `Keynako.inputmethod`, an InputMethodKit server with
marked text, candidates, Japanese/English modes, live conversion, the cached
Keynako shared dictionary and Zenzai. The input menu uses the Flutter app icon
and offers `あ`/`A` mode and live-conversion controls.
Install it in `~/Library/Input Methods`, then log out and back in before adding
Keynako in System Settings > Keyboard > Input Sources.
