# macOS InputMethodKit adapter

The build script creates `Keynako.inputmethod`, an InputMethodKit server with
marked text, candidates, Japanese/English modes, live conversion, the bundled
AzooKey default dictionary, the cached and bundled `Dictionary/data_v1.json`
shared dictionary, and Zenzai. The input menu uses the Flutter app icon and
offers `あ`/`A` mode and live-conversion controls.
It also offers a manual shared-dictionary refresh and requests a non-visual
refresh at most once every five minutes while the input method is in use. The
install script places the companion app in `~/Applications` for this updater.
Install it in `~/Library/Input Methods`, then log out and back in before adding
Keynako in System Settings > Keyboard > Input Sources.
