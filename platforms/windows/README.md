# Windows TSF adapter

`KeynakoIME.dll` is a 64-bit, in-process Text Services Framework text service.
It owns composition, Japanese/English input mode, live conversion, candidate
selection, the shared Keynako dictionary and optional Zenzai conversion.
`Space` and the Japanese Convert key start/cycle conversion. With no active
composition, Convert toggles Japanese/English mode; `Ctrl+Space` does the same.

The Windows Input Indicator shows the app branding icon and a separate `あ` or
`A` mode item through `GUID_LBI_INPUTMODE`. Its menu switches Japanese,
alphanumeric and live-conversion modes. The candidate window shows numbered,
paged candidates and their shared-dictionary or Zenzai source in a rounded,
system-colored panel with keyboard guidance.

The release artifact is `KeynakoSetup.exe`. It installs the Flutter settings
app, TSF DLL, Zenzai helper and models, the AzooKey default dictionary, and a
build-time `Dictionary/data_v1.json` snapshot below Program Files. It registers
the input service and creates an executable uninstaller that also removes the
updated dictionary cache. The PowerShell files remain available for development
and recovery.
