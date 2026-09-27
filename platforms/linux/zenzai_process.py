"""Bounded request/response protocol for the Linux Zenzai helper."""

from __future__ import annotations

import binascii
import os
from pathlib import Path
import select
import subprocess
import threading
import time
from typing import Callable


class Zenzai:
    def __init__(
        self,
        executable: Path | None = None,
        model: Path | None = None,
        ready_timeout: float = 15.0,
        response_timeout: float = 15.0,
    ) -> None:
        root = Path(__file__).resolve().parent
        self.executable = executable or Path(os.environ.get(
            "KEYNAKO_ZENZAI_BIN", root / "keynako_zenzai",
        ))
        self.model = model or Path(os.environ.get(
            "KEYNAKO_ZENZAI_MODEL",
            root / "zenzai" / "zenz-v3.2-xsmall-gguf" / "ggml-model-Q5_K_M.gguf",
        ))
        self.ready_timeout = ready_timeout
        self.response_timeout = response_timeout
        self.process: subprocess.Popen[bytes] | None = None
        self._stdout_buffer = bytearray()

    def _readline(self, timeout: float) -> bytes | None:
        process = self.process
        if process is None or process.stdout is None:
            return None
        deadline = time.monotonic() + timeout
        while True:
            end = self._stdout_buffer.find(b"\n")
            if end >= 0:
                line = bytes(self._stdout_buffer[:end]).rstrip(b"\r")
                del self._stdout_buffer[:end + 1]
                return line
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            readable, _, _ = select.select([process.stdout], [], [], remaining)
            if not readable:
                return None
            chunk = os.read(process.stdout.fileno(), 4096)
            if not chunk:
                return None
            self._stdout_buffer.extend(chunk)
            if len(self._stdout_buffer) > 64 * 1024:
                return None

    def _start(self) -> bool:
        if self.process is not None:
            if self.process.poll() is None:
                return True
            self.close(graceful=False)
        if not self.executable.is_file() or not self.model.is_file():
            return False
        try:
            self.process = subprocess.Popen(
                [str(self.executable), str(self.model)],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
            )
            self._stdout_buffer.clear()
            if self._readline(self.ready_timeout) == b"READY":
                return True
        except (OSError, ValueError):
            pass
        self.close(graceful=False)
        return False

    def generate(self, reading: str) -> str | None:
        if not reading or len(reading.encode("utf-8")) > 1024:
            return None
        if not self._start() or self.process is None or self.process.stdin is None:
            return None
        prompt = "\uee00" + reading + "\uee01"
        try:
            self.process.stdin.write(b"24\t" + binascii.hexlify(prompt.encode()) + b"\n")
            self.process.stdin.flush()
            response = self._readline(self.response_timeout)
            if not response or response.startswith(b"ERROR"):
                self.close(graceful=False)
                return None
            value = binascii.unhexlify(response).decode("utf-8", "replace")
            for marker in range(0xEE00, 0xEE08):
                value = value.split(chr(marker), 1)[0]
            return value.strip() or None
        except (BrokenPipeError, OSError, ValueError):
            self.close(graceful=False)
            return None

    def close(self, graceful: bool = True) -> None:
        process = self.process
        self.process = None
        self._stdout_buffer.clear()
        if process is None:
            return
        try:
            if process.poll() is None and graceful and process.stdin is not None:
                try:
                    process.stdin.write(b"QUIT\n")
                    process.stdin.flush()
                    process.wait(timeout=1)
                except (BrokenPipeError, OSError, subprocess.TimeoutExpired):
                    pass
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=1)
            else:
                process.wait()
        except (OSError, subprocess.TimeoutExpired):
            try:
                process.kill()
                process.wait(timeout=1)
            except (OSError, subprocess.TimeoutExpired):
                pass
        finally:
            for pipe in (process.stdin, process.stdout):
                if pipe is not None:
                    try:
                        pipe.close()
                    except OSError:
                        pass


class AsyncZenzai:
    """Run inference off the IBus thread and dispatch results on its event loop."""

    def __init__(
        self,
        dispatch: Callable[[Callable[[], bool]], object],
        engine_factory: Callable[[], Zenzai] = Zenzai,
    ) -> None:
        self._dispatch = dispatch
        self._engine_factory = engine_factory
        self._lock = threading.Lock()
        self._wake = threading.Event()
        self._pending: tuple[str, Callable[[str | None], None]] | None = None
        self._thread: threading.Thread | None = None
        self._closed = False

    def submit(self, reading: str, callback: Callable[[str | None], None]) -> None:
        with self._lock:
            if self._closed:
                return
            # Keep only the newest request while a previous inference is running.
            self._pending = (reading, callback)
            if self._thread is None:
                self._thread = threading.Thread(target=self._run, daemon=True)
                self._thread.start()
            self._wake.set()

    def _run(self) -> None:
        engine = self._engine_factory()
        try:
            while True:
                self._wake.wait()
                with self._lock:
                    if self._closed:
                        return
                    request = self._pending
                    self._pending = None
                    self._wake.clear()
                if request is None:
                    continue
                reading, callback = request
                try:
                    result = engine.generate(reading)
                except Exception:
                    result = None
                with self._lock:
                    stale = self._closed or self._pending is not None
                if not stale:
                    self._dispatch(lambda: self._deliver(callback, result))
        finally:
            engine.close()

    def _deliver(self, callback: Callable[[str | None], None], result: str | None) -> bool:
        with self._lock:
            closed = self._closed
        if not closed:
            callback(result)
        return False

    def close(self) -> None:
        with self._lock:
            self._closed = True
            self._pending = None
            self._wake.set()
