# Windows TSF adapter

`KeynakoIME.dll` is a 64-bit, in-process Text Services Framework text service.
It owns composition, Japanese/English input mode, live conversion, candidate
selection and optional Zenzai conversion. `Ctrl+Space` switches language mode.

The release artifact is `KeynakoSetup.exe`. It installs the Flutter settings
app, TSF DLL, Zenzai helper and models below Program Files, registers
the input service, and creates an executable uninstaller. The PowerShell files
remain available for development and recovery.
