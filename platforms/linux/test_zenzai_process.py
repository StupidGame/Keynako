"""Regression tests for the Linux helper protocol without an IBus session."""

import importlib
from pathlib import Path
import sys
import threading
import tempfile
import time
import types
import unittest
from unittest import mock

from zenzai_process import AsyncZenzai, Zenzai


class ZenzaiProcessTest(unittest.TestCase):
    def test_late_result_only_changes_the_original_conversion(self) -> None:
        gi = types.ModuleType("gi")
        gi.require_version = lambda *_: None
        repository = types.ModuleType("gi.repository")
        repository.GLib = types.SimpleNamespace()
        repository.IBus = types.SimpleNamespace(Engine=object, Factory=object)
        with mock.patch.dict(sys.modules, {"gi": gi, "gi.repository": repository}):
            sys.modules.pop("keynako_engine", None)
            keynako_engine = importlib.import_module("keynako_engine")
        sys.modules.pop("keynako_engine", None)

        class FakeSession:
            def __init__(self) -> None:
                self.inserted = []
                self.selected = []

            def is_converting(self) -> bool:
                return True

            def reading(self) -> str:
                return "あ"

            def insert_zenzai(self, value: str) -> None:
                self.inserted.append(value)

            def select(self, index: int) -> None:
                self.selected.append(index)

        engine = keynako_engine.KeynakoEngine.__new__(keynako_engine.KeynakoEngine)
        engine.session = FakeSession()
        engine.raw = "a"
        engine.mode = "ja"
        engine._conversion_revision = 2
        engine._selection_revision = 0
        engine._destroyed = False
        rendered = []
        engine._render = lambda: rendered.append(True)

        engine._receive_zenzai(1, 0, "あ", "old")
        self.assertEqual(engine.session.inserted, [])
        engine._receive_zenzai(2, 0, "あ", "new")
        self.assertEqual(engine.session.inserted, ["new"])
        self.assertEqual(engine.session.selected, [0])
        engine._selection_revision = 1
        engine._receive_zenzai(2, 0, "あ", "later")
        self.assertEqual(engine.session.inserted, ["new", "later"])
        self.assertEqual(engine.session.selected, [0])
        engine._destroyed = True
        engine._receive_zenzai(2, 1, "あ", "destroyed")
        self.assertEqual(rendered, [True, True])

    def test_async_inference_does_not_block_and_only_delivers_latest_request(self) -> None:
        started = threading.Event()
        release = threading.Event()
        closed = threading.Event()
        callbacks = []
        results = []

        class FakeEngine:
            def generate(self, reading: str) -> str:
                if reading == "old":
                    started.set()
                    release.wait(2)
                return reading.upper()

            def close(self) -> None:
                closed.set()

        engine = AsyncZenzai(callbacks.append, FakeEngine)
        try:
            began = time.monotonic()
            engine.submit("old", results.append)
            self.assertLess(time.monotonic() - began, 0.2)
            self.assertTrue(started.wait(1))
            engine.submit("skipped", results.append)
            engine.submit("new", results.append)
            release.set()
            deadline = time.monotonic() + 2
            while not callbacks and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertEqual(len(callbacks), 1)
            callbacks.pop()()
            self.assertEqual(results, ["NEW"])
        finally:
            release.set()
            engine.close()
            self.assertTrue(closed.wait(1))

    def test_async_close_drops_queued_result(self) -> None:
        started = threading.Event()
        release = threading.Event()
        closed = threading.Event()
        callbacks = []

        class FakeEngine:
            def generate(self, reading: str) -> str:
                started.set()
                release.wait(2)
                return reading

            def close(self) -> None:
                closed.set()

        engine = AsyncZenzai(callbacks.append, FakeEngine)
        engine.submit("old", lambda _: self.fail("closed engine delivered a result"))
        self.assertTrue(started.wait(1))
        engine.close()
        release.set()
        self.assertTrue(closed.wait(1))
        self.assertEqual(callbacks, [])

    def test_overlong_reading_is_rejected_before_startup(self) -> None:
        engine = Zenzai()
        self.assertIsNone(engine.generate("あ" * 1400))
        self.assertIsNone(engine.process)

    def test_startup_timeout_does_not_block_indefinitely(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            helper = root / "helper.sh"
            helper.write_text("#!/bin/sh\nread line\n", encoding="utf-8")
            helper.chmod(0o755)
            model = root / "model"
            model.touch()
            engine = Zenzai(helper, model, ready_timeout=0.1, response_timeout=0.1)

            started = time.monotonic()
            self.assertIsNone(engine.generate("あ"))
            self.assertLess(time.monotonic() - started, 2.0)
            self.assertIsNone(engine.process)

    def test_timed_out_response_restarts_the_helper(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            helper = root / "helper.sh"
            helper.write_text(
                "#!/bin/sh\n"
                "marker=\"$1.marker\"\n"
                "printf 'READY\\n'\n"
                "if [ ! -f \"$marker\" ]; then\n"
                "  : > \"$marker\"\n"
                "  read line\n"
                "  read line\n"
                "else\n"
                "  while read line; do\n"
                "    [ \"$line\" = QUIT ] && exit 0\n"
                "    printf '41\\n'\n"
                "  done\n"
                "fi\n",
                encoding="utf-8",
            )
            helper.chmod(0o755)
            model = root / "model"
            model.touch()
            engine = Zenzai(helper, model, ready_timeout=0.5, response_timeout=0.1)
            try:
                self.assertIsNone(engine.generate("あ"))
                self.assertEqual(engine.generate("あ"), "A")
                self.assertEqual(engine.generate("い"), "A")
            finally:
                engine.close()


if __name__ == "__main__":
    unittest.main()
