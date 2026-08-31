# Windows TSF adapter

`KeynakoIME.dll` is a 64-bit, in-process Text Services Framework text service.
It owns composition, Japanese/English input mode, live conversion, candidate
selection, the shared Keynako dictionary and optional Zenzai conversion.
`Space` and the Japanese Convert key start/cycle conversion. With no active
composition, Convert toggles Japanese/English mode on both JIS and US layouts.
The physical JIS Convert scan code is also recognized when a US layout does not
map that key to `VK_CONVERT`.
US keyboards without a Convert key can use `Alt+Backquote` (the Microsoft IME
shortcut) or `Ctrl+Space` for the same toggle.

The Windows Input Indicator and keyboard-layout picker use the Android-matching
app icon, and a separate `あ` or `A` mode item through `GUID_LBI_INPUTMODE`.
Re-registration refreshes the profile icon cached by Windows. Its menu switches Japanese,
alphanumeric and live-conversion modes. The candidate window shows numbered,
paged candidates and their shared-dictionary or Zenzai source in a rounded,
system-colored panel with keyboard guidance.

The release artifact is `KeynakoSetup.exe`. It installs the Flutter settings
app, TSF DLL, Zenzai helper and models, the AzooKey default dictionary, and a
build-time `Dictionary/data_v1.json` snapshot below Program Files. It registers
the input service and creates an executable uninstaller that also removes the
updated dictionary cache. The PowerShell files remain available for development
and recovery. Each installer build gives the in-process TSF DLL a unique file
name, so upgrades never overwrite a copy loaded by Explorer. Restart Manager is
restricted to the Keynako settings app and never closes Explorer.
