# Windows TSF adapter

`KeynakoIME.dll` is a 64-bit, in-process Text Services Framework text service.
It owns composition, Japanese/English input mode, live conversion, candidate
selection, the shared Keynako dictionary and optional Zenzai conversion.
`Space` starts/cycles conversion. The Japanese Convert key mirrors that behavior
only while a composition exists; it is never used as an input-mode toggle.
Hankaku/Zenkaku toggles Japanese/English mode while preserving the current composition
and rebuilding its candidates for the selected mode when Windows reports that key
through TSF. Keynako does not install a Windows keyboard hook. A US 101/102-key
keyboard keeps bare Backquote available for text entry and can toggle with
`Alt+Backquote` (the Microsoft IME shortcut) or `Ctrl+Space`. The TSF key sink and
preserved-key routes also handle the explicit IME on/off and DBE
half-width/full-width virtual-key variants.
Slash and `Shift+Slash` are translated through the active layout, so `/` and `?`
work with both Japanese and US keyboards.
The TIP also publishes its candidates through the TSF UI-less interfaces. Games
and other full-screen clients that render IME candidates themselves can activate
Keynako, receive the candidate list, change its selection, and finalize it.

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
The desktop app performs periodic cache refreshes. The TIP only reloads the newest
local cache while typing, so a focused application never spawns a dictionary-refresh
process in response to a key event.

Windows loads a TSF text-service DLL inside the focused application. Every Actions
artifact therefore carries an Authenticode signature on the TIP, its Keynako
helper executables, and the installer. Pull-request and manual builds use a cached
self-signed CI certificate; release tags use the trusted certificate from repository
secrets when one is configured. A CI signature provides integrity but is not a
trusted publisher identity. Protected games can still apply their own allowlist,
so even a trusted signature cannot guarantee acceptance by every anti-cheat product.

When `KEYNAKO_DICTIONARY_SUBMISSION_URL` is set to an HTTPS URL at CMake
configure time, committing a non-first dictionary candidate shows an eight-second
confirmation panel. Clicking it posts only the selected word, reading, candidate
rank and build version to the shared conversion dictionary gateway. Surrounding
text and host-application details are never included. Builds without the endpoint
do not show the panel.

The release artifact is `KeynakoSetup.exe`. It installs the Flutter settings
app, TSF DLL, Zenzai helper and models, the AzooKey default dictionary, and a
build-time `Dictionary/data_v1.json` snapshot below Program Files. It registers
the input service and creates an executable uninstaller that also removes the
updated dictionary cache. The PowerShell files remain available for development
and recovery. Each installer build gives the in-process TSF DLL a unique file
name, so upgrades never overwrite a copy loaded by Explorer. The Zenzai helper
keeps its stable file name; Setup closes only that Keynako process before
replacing it and reuses existing model files. Restart Manager never closes
Explorer.
