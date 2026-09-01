# Windows TSF adapter

`KeynakoIME.dll` is a 64-bit, in-process Text Services Framework text service.
It owns composition, Japanese/English input mode, live conversion, candidate
selection, the shared Keynako dictionary and optional Zenzai conversion.
`Space` starts/cycles conversion. The Japanese Convert key mirrors that behavior
only while a composition exists; it is never used as an input-mode toggle.
Hankaku/Zenkaku toggles Japanese/English mode. A thread-local `WH_KEYBOARD` hook
accepts its physical JIS scan code on a Windows keyboard reported as Japanese,
even while the logical layout is US. A real US 101/102-key keyboard keeps bare
Backquote available for text entry and can toggle with `Alt+Backquote` (the
Microsoft IME shortcut) or `Ctrl+Space`. If the hook is unavailable, the normal
TSF key sink and preserved-key routes remain active.

The Windows Input Indicator and keyboard-layout picker use the Android-matching
app icon, and a separate `あ` or `A` mode item through `GUID_LBI_INPUTMODE`.
Re-registration refreshes the profile icon cached by Windows. Its menu switches Japanese,
alphanumeric and live-conversion modes. The candidate window shows numbered,
paged candidates and their shared-dictionary or Zenzai source in a rounded,
system-colored panel with keyboard guidance.
Right-clicking a candidate sends its word and reading to the same configured
Keynako shared-dictionary HTTPS gateway used by the app. Network work runs in a
small out-of-process helper, so the focused application and TSF thread do not
block on the request.
The input-indicator menu can also refresh the shared dictionary immediately.
While the IME is in use it requests a cache refresh at most once every five
minutes through the desktop app's non-visual command mode, then reloads the
newest per-user cache without blocking the focused application.

The release artifact is `KeynakoSetup.exe`. It installs the Flutter settings
app, TSF DLL, Zenzai helper and models, the AzooKey default dictionary, and a
build-time `Dictionary/data_v1.json` snapshot below Program Files. It registers
the input service and creates an executable uninstaller that also removes the
updated dictionary cache. The PowerShell files remain available for development
and recovery. Each installer build gives the in-process TSF DLL a unique file
name, so upgrades never overwrite a copy loaded by Explorer. Restart Manager is
restricted to the Keynako settings app and never closes Explorer.
