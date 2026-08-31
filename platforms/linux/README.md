# Linux IBus adapter

`keynako_engine.py` is an IBus engine that publishes preedit text and a native
lookup table. Conversion state comes from the shared C++ core through
`libkeynako_ime_bridge.so`; the Python layer only maps IBus events and UI. It
supports Japanese and English modes, an `あ`/`A` panel property, live
candidates, the bundled AzooKey default dictionary, the cached and bundled
`Dictionary/data_v1.json` shared dictionary, and the bundled Zenzai helper.
The IBus source selector uses the same icon as the Flutter app. The user-local
installer does not require root access.
