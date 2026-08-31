# Windows TSF adapter

`KeynakoIME.dll` is a 64-bit, in-process Text Services Framework text service.
It owns composition, Japanese/English input mode, live conversion, candidate
selection, the shared Keynako dictionary and optional Zenzai conversion.
`Space` and the Japanese Convert key start/cycle conversion, while
`Ctrl+Space` switches language mode.

The Windows Input Indicator shows the app branding icon and a separate `あ` or
`A` mode item through `GUID_LBI_INPUTMODE`. Its menu switches Japanese,
alphanumeric and live-conversion modes. The candidate window shows numbered,
paged candidates and their shared-dictionary or Zenzai source in a rounded,
system-colored panel with keyboard guidance.

The release artifact is `KeynakoSetup.exe`. It installs the Flutter settings
app, TSF DLL, Zenzai helper and models below Program Files, registers
the input service, and creates an executable uninstaller. The PowerShell files
remain available for development and recovery.
