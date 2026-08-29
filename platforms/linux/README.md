# Linux IBus adapter

`keynako_engine.py` is an IBus engine that publishes preedit text and a native
lookup table. Conversion state comes from the shared C++ core through
`libkeynako_ime_bridge.so`; the Python layer only maps IBus events and UI. It
supports Japanese and English modes, live candidates and the bundled Zenzai
helper. The user-local installer does not require root access.
