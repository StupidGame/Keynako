"""Regression tests for the Linux helper protocol without an IBus session."""

from pathlib import Path
import tempfile
import time
import unittest

from zenzai_process import Zenzai


class ZenzaiProcessTest(unittest.TestCase):
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
