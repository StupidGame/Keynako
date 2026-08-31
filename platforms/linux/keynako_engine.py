#!/usr/bin/env python3
"""IBus adapter for the shared Keynako desktop input engine."""

from __future__ import annotations

import binascii
import ctypes
import os
from pathlib import Path
import subprocess
import sys
import time

import gi

gi.require_version("IBus", "1.0")
from gi.repository import GLib, IBus  # noqa: E402


class NativeSession:
    """Small ctypes owner for the platform-neutral C++ IME state machine."""

    def __init__(self) -> None:
        library_path = Path(os.environ.get(
            "KEYNAKO_IME_CORE",
            Path(__file__).resolve().parent / "libkeynako_ime_bridge.so",
        ))
        self.library = ctypes.CDLL(str(library_path))
        self.library.keynako_ime_create.restype = ctypes.c_void_p
        self.library.keynako_ime_destroy.argtypes = [ctypes.c_void_p]
        self.library.keynako_ime_set_mode.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.library.keynako_ime_append_ascii.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.library.keynako_ime_backspace.argtypes = [ctypes.c_void_p]
        self.library.keynako_ime_clear.argtypes = [ctypes.c_void_p]
        self.library.keynako_ime_begin_conversion.argtypes = [ctypes.c_void_p]
        self.library.keynako_ime_begin_conversion.restype = ctypes.c_int
        self.library.keynako_ime_cancel_conversion.argtypes = [ctypes.c_void_p]
        self.library.keynako_ime_cancel_conversion.restype = ctypes.c_int
        self.library.keynako_ime_is_converting.argtypes = [ctypes.c_void_p]
        self.library.keynako_ime_is_converting.restype = ctypes.c_int
        self.library.keynako_ime_load_user_dictionary.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        self.library.keynako_ime_load_user_dictionary.restype = ctypes.c_int
        self.library.keynako_ime_set_bundled_dictionary_path.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        self.library.keynako_ime_set_bundled_dictionary_path.restype = ctypes.c_int
        for name in ("keynako_ime_reading", "keynako_ime_display_text", "keynako_ime_selected_text"):
            function = getattr(self.library, name)
            function.argtypes = [ctypes.c_void_p]
            function.restype = ctypes.c_char_p
        self.library.keynako_ime_candidate_count.argtypes = [ctypes.c_void_p]
        self.library.keynako_ime_candidate_count.restype = ctypes.c_size_t
        self.library.keynako_ime_candidate_at.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
        self.library.keynako_ime_candidate_at.restype = ctypes.c_char_p
        self.library.keynako_ime_selected_index.argtypes = [ctypes.c_void_p]
        self.library.keynako_ime_selected_index.restype = ctypes.c_size_t
        self.library.keynako_ime_select_next.argtypes = [ctypes.c_void_p]
        self.library.keynako_ime_select_previous.argtypes = [ctypes.c_void_p]
        self.library.keynako_ime_insert_zenzai.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        self.handle = self.library.keynako_ime_create()
        if not self.handle:
            raise RuntimeError("could not create Keynako IME session")
        dictionary_root = Path(__file__).resolve().parent / "azookey_dictionary" / "Dictionary"
        self.library.keynako_ime_set_bundled_dictionary_path(
            self.handle, os.fsencode(dictionary_root),
        )

    def close(self) -> None:
        if self.handle:
            self.library.keynako_ime_destroy(self.handle)
            self.handle = None

    def set_mode(self, english: bool) -> None:
        self.library.keynako_ime_set_mode(self.handle, int(english))

    def append(self, value: str) -> None:
        self.library.keynako_ime_append_ascii(self.handle, ord(value))

    def backspace(self) -> None:
        self.library.keynako_ime_backspace(self.handle)

    def clear(self) -> None:
        self.library.keynako_ime_clear(self.handle)

    def begin_conversion(self) -> bool:
        return bool(self.library.keynako_ime_begin_conversion(self.handle))

    def cancel_conversion(self) -> bool:
        return bool(self.library.keynako_ime_cancel_conversion(self.handle))

    def is_converting(self) -> bool:
        return bool(self.library.keynako_ime_is_converting(self.handle))

    def load_user_dictionary(self, path: Path) -> bool:
        return bool(self.library.keynako_ime_load_user_dictionary(
            self.handle, os.fsencode(path),
        ))

    def reading(self) -> str:
        return self.library.keynako_ime_reading(self.handle).decode()

    def selected_text(self) -> str:
        return self.library.keynako_ime_selected_text(self.handle).decode()

    def display_text(self) -> str:
        return self.library.keynako_ime_display_text(self.handle).decode()

    def candidates(self) -> list[str]:
        count = self.library.keynako_ime_candidate_count(self.handle)
        return [self.library.keynako_ime_candidate_at(self.handle, index).decode() for index in range(count)]

    def selected_index(self) -> int:
        return self.library.keynako_ime_selected_index(self.handle)

    def select_next(self) -> None:
        self.library.keynako_ime_select_next(self.handle)

    def select_previous(self) -> None:
        self.library.keynako_ime_select_previous(self.handle)

    def select(self, index: int) -> None:
        count = len(self.candidates())
        if count:
            while self.selected_index() != index % count:
                self.select_next()

    def insert_zenzai(self, value: str) -> None:
        self.library.keynako_ime_insert_zenzai(self.handle, value.encode())


class Zenzai:
    def __init__(self) -> None:
        self.process: subprocess.Popen[bytes] | None = None

    def _start(self) -> bool:
        if self.process is not None:
            return True
        root = Path(__file__).resolve().parent
        executable = Path(os.environ.get("KEYNAKO_ZENZAI_BIN", root / "keynako_zenzai"))
        model = Path(os.environ.get(
            "KEYNAKO_ZENZAI_MODEL",
            root / "zenzai" / "zenz-v3.2-xsmall-gguf" / "ggml-model-Q5_K_M.gguf",
        ))
        if not executable.is_file() or not model.is_file():
            return False
        self.process = subprocess.Popen(
            [str(executable), str(model)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        if self.process.stdout is not None and self.process.stdout.readline().strip() == b"READY":
            return True
        self.close()
        return False

    def generate(self, reading: str) -> str | None:
        if not self._start() or self.process is None or self.process.stdin is None or self.process.stdout is None:
            return None
        prompt = "\uee00" + reading + "\uee01"
        try:
            self.process.stdin.write(b"24\t" + binascii.hexlify(prompt.encode()) + b"\n")
            self.process.stdin.flush()
            response = self.process.stdout.readline().strip()
            if not response or response.startswith(b"ERROR"):
                return None
            value = binascii.unhexlify(response).decode("utf-8", "replace")
            for marker in range(0xEE00, 0xEE08):
                value = value.split(chr(marker), 1)[0]
            return value.strip() or None
        except (BrokenPipeError, OSError, ValueError):
            return None

    def close(self) -> None:
        if self.process is None:
            return
        try:
            self.process.communicate(b"QUIT\n", timeout=1)
        except (OSError, subprocess.TimeoutExpired):
            self.process.kill()
        self.process = None


class KeynakoEngine(IBus.Engine):
    def __init__(self, connection: object, object_path: str) -> None:
        super().__init__(connection=connection, object_path=object_path)
        self.session = NativeSession()
        self.raw = ""
        self.mode = "ja"
        self.lookup = IBus.LookupTable.new(9, 0, True, True)
        self.zenzai = Zenzai()
        self.dictionary_path: Path | None = None
        self.dictionary_mtime_ns = -1
        self.last_dictionary_check = 0.0
        self._reload_shared_dictionary(force=True)
        self.mode_property = IBus.Property.new(
            "InputMode",
            IBus.PropType.NORMAL,
            IBus.Text.new_from_string("あ"),
            "",
            IBus.Text.new_from_string("Keynako ひらがな"),
            True,
            True,
            IBus.PropState.UNCHECKED,
            None,
        )
        properties = IBus.PropList()
        properties.append(self.mode_property)
        self.register_properties(properties)

    def _dictionary_candidates(self) -> list[Path]:
        xdg = os.environ.get("XDG_DATA_HOME")
        home = Path.home()
        candidates = []
        if xdg:
            candidates.append(Path(xdg) / "keynako" / "shared_dictionary.tsv")
        candidates.append(home / ".local" / "share" / "keynako" / "shared_dictionary.tsv")
        candidates.append(Path(__file__).resolve().parent / "bundled_shared_dictionary.tsv")
        return candidates

    def _reload_shared_dictionary(self, force: bool = False) -> None:
        now = time.monotonic()
        if not force and now - self.last_dictionary_check < 5:
            return
        self.last_dictionary_check = now
        for path in self._dictionary_candidates():
            try:
                mtime_ns = path.stat().st_mtime_ns
            except OSError:
                continue
            if path == self.dictionary_path and mtime_ns == self.dictionary_mtime_ns:
                return
            if self.session.load_user_dictionary(path):
                self.dictionary_path = path
                self.dictionary_mtime_ns = mtime_ns
                return

    def _update_mode_property(self) -> None:
        japanese = self.mode == "ja"
        self.mode_property.set_label(IBus.Text.new_from_string("あ" if japanese else "A"))
        self.mode_property.set_tooltip(IBus.Text.new_from_string(
            "Keynako ひらがな" if japanese else "Keynako 英数",
        ))
        self.update_property(self.mode_property)

    def _render(self) -> None:
        candidates = self.session.candidates()
        if not self.raw or not candidates:
            self.update_preedit_text(IBus.Text.new_from_string(""), 0, False)
            self.hide_lookup_table()
            return
        selected = self.session.selected_index()
        visible = self.session.display_text()
        self.update_preedit_text(IBus.Text.new_from_string(visible), len(visible), True)
        if not self.session.is_converting():
            self.hide_lookup_table()
            return
        self.lookup.clear()
        for candidate in candidates:
            self.lookup.append_candidate(IBus.Text.new_from_string(candidate))
        self.lookup.set_cursor_pos(selected)
        self.update_lookup_table(self.lookup, True)

    def _clear(self) -> None:
        self.raw = ""
        self.session.clear()
        self._render()

    def _commit(self) -> None:
        if not self.raw:
            return
        suffix = " " if self.mode == "en" else ""
        self.commit_text(IBus.Text.new_from_string(self.session.selected_text() + suffix))
        self._clear()

    def do_process_key_event(self, keyval: int, keycode: int, state: int) -> bool:
        del keycode
        if state & IBus.ModifierType.RELEASE_MASK:
            return False
        control = bool(state & IBus.ModifierType.CONTROL_MASK)
        if control and keyval == IBus.KEY_space:
            self.mode = "en" if self.mode == "ja" else "ja"
            self.session.set_mode(self.mode == "en")
            self.raw = ""
            self._update_mode_property()
            self._render()
            return True
        if control or state & (IBus.ModifierType.MOD1_MASK | IBus.ModifierType.MOD4_MASK):
            return False
        if keyval == IBus.KEY_BackSpace:
            if not self.raw:
                return False
            if not self.session.cancel_conversion():
                self.raw = self.raw[:-1]
                self.session.backspace()
            self._render()
            return True
        if keyval == IBus.KEY_Escape:
            if not self.raw:
                return False
            if self.session.cancel_conversion():
                self._render()
            else:
                self._clear()
            return True
        if keyval in (IBus.KEY_Return, IBus.KEY_KP_Enter):
            if not self.raw:
                return False
            self._commit()
            return True
        conversion_keys = (
            IBus.KEY_space,
            IBus.KEY_Down,
            IBus.KEY_Up,
            getattr(IBus, "KEY_Henkan", -1),
            getattr(IBus, "KEY_Henkan_Mode", -1),
        )
        if keyval in conversion_keys:
            if not self.raw:
                if keyval in (
                    getattr(IBus, "KEY_Henkan", -1),
                    getattr(IBus, "KEY_Henkan_Mode", -1),
                ):
                    self.mode = "en" if self.mode == "ja" else "ja"
                    self.session.set_mode(self.mode == "en")
                    self._update_mode_property()
                    self._render()
                    return True
                return False
            self._reload_shared_dictionary()
            if not self.session.is_converting():
                if keyval in (
                    IBus.KEY_space,
                    getattr(IBus, "KEY_Henkan", -1),
                    getattr(IBus, "KEY_Henkan_Mode", -1),
                ) and self.mode == "ja":
                    generated = self.zenzai.generate(self.session.reading())
                    if generated:
                        self.session.insert_zenzai(generated)
                self.session.begin_conversion()
                if keyval == IBus.KEY_Up:
                    self.session.select_previous()
            else:
                if keyval == IBus.KEY_Up:
                    self.session.select_previous()
                else:
                    self.session.select_next()
            self._render()
            return True
        scalar = IBus.keyval_to_unicode(keyval)
        if scalar and chr(scalar).lower() in "abcdefghijklmnopqrstuvwxyz-,.":
            if self.mode == "en":
                return False
            value = chr(scalar)
            self._reload_shared_dictionary()
            self.raw += value
            self.session.append(value)
            self._render()
            return True
        return False

    def do_candidate_clicked(self, index: int, button: int, state: int) -> None:
        del button, state
        if 0 <= index < len(self.session.candidates()):
            self.session.select(index)
            self._commit()

    def do_property_activate(self, prop_name: str, prop_state: int) -> None:
        del prop_state
        if prop_name != "InputMode":
            return
        self.mode = "en" if self.mode == "ja" else "ja"
        self.session.set_mode(self.mode == "en")
        self.raw = ""
        self._update_mode_property()
        self._render()

    def do_cursor_up(self) -> bool:
        if not self.raw:
            return False
        self.session.select_previous()
        self._render()
        return True

    def do_cursor_down(self) -> bool:
        if not self.raw:
            return False
        self.session.select_next()
        self._render()
        return True

    def do_reset(self) -> None:
        self._clear()

    def do_focus_out(self) -> None:
        if self.raw:
            self._commit()
        self.hide_lookup_table()
        super().do_focus_out()

    def do_destroy(self) -> None:
        self.zenzai.close()
        self.session.close()
        super().do_destroy()


class EngineFactory(IBus.Factory):
    def __init__(self, bus: IBus.Bus) -> None:
        super().__init__(connection=bus.get_connection(), object_path=IBus.PATH_FACTORY)
        self.counter = 0

    def do_create_engine(self, engine_name: str) -> KeynakoEngine:
        if engine_name != "keynako":
            raise ValueError(f"unknown engine: {engine_name}")
        self.counter += 1
        return KeynakoEngine(
            self.get_connection(), f"/org/freedesktop/IBus/Keynako/Engine/{self.counter}",
        )


def main() -> int:
    IBus.init()
    bus = IBus.Bus.new()
    if not bus.is_connected():
        print("Keynako could not connect to IBus", file=sys.stderr)
        return 1
    factory = EngineFactory(bus)
    bus.request_name("org.freedesktop.IBus.Keynako", 0)
    loop = GLib.MainLoop()
    bus.connect("disconnected", lambda _: loop.quit())
    loop.run()
    del factory
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
