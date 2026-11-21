"""Offline regression tests for dictionary compatibility and safe updates."""

from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import update_azookey_dictionary as updater


def dictionary_fixture(repo: Path) -> None:
    (repo / "LICENSE").write_text("Apache License\nVersion 2.0", encoding="utf-8")
    root = repo / "Dictionary"
    (root / "louds").mkdir(parents=True)
    (root / "cb").mkdir()
    (root / "louds/charID.chid").write_text("アイウ", encoding="utf-8")
    (root / "mm.binary").write_bytes(bytes(4))
    for cid in range(1319):
        (root / f"cb/{cid}.binary").write_bytes(bytes(8))
    (root / "louds/ア.louds").write_bytes(bytes(8))
    (root / "louds/ア.loudschars2").write_bytes(bytes(3))
    (root / "louds/ア0.loudstxt3").write_bytes(bytes(8))


class DictionaryValidationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        dictionary_fixture(self.repo)

    def test_accepts_compatible_dictionary(self):
        updater.validate(self.repo)

    def test_rejects_missing_files(self):
        for relative in ("cb/1318.binary", "louds/ア0.loudstxt3"):
            with self.subTest(relative=relative):
                path = self.repo / "Dictionary" / relative
                original = path.read_bytes()
                path.unlink()
                with self.assertRaises(FileNotFoundError):
                    updater.validate(self.repo)
                path.write_bytes(original)

    def test_rejects_truncated_binary(self):
        for relative in ("mm.binary", "cb/0.binary", "louds/ア.louds"):
            with self.subTest(relative=relative):
                path = self.repo / "Dictionary" / relative
                original = path.read_bytes()
                path.write_bytes(b"x")
                with self.assertRaises(ValueError):
                    updater.validate(self.repo)
                path.write_bytes(original)

    def test_rejects_incompatible_character_table(self):
        for text in ("アイア", "", "".join(chr(0x3040 + i) for i in range(257))):
            with self.subTest(length=len(text)):
                (self.repo / "Dictionary/louds/charID.chid").write_text(text, encoding="utf-8")
                with self.assertRaises(ValueError):
                    updater.validate(self.repo)

    def test_rejects_missing_shards(self):
        (self.repo / "Dictionary/louds/ア.louds").unlink()
        with self.assertRaises(ValueError):
            updater.validate(self.repo)

    def test_rejects_license_change(self):
        (self.repo / "LICENSE").write_text("Different license", encoding="utf-8")
        with self.assertRaises(ValueError):
            updater.validate(self.repo)


class DictionaryUpdateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.upstream = self.root / "upstream"
        self.upstream.mkdir()
        updater.git(self.upstream, "init", "-b", "main")
        updater.git(self.upstream, "config", "user.name", "Test")
        updater.git(self.upstream, "config", "user.email", "test@example.invalid")
        dictionary_fixture(self.upstream)
        self.commit("Initial dictionary")
        self.old = updater.git(self.upstream, "rev-parse", "HEAD")
        self.local = self.root / updater.SUBMODULE
        self.local.parent.mkdir(parents=True)
        updater.git(self.root, "clone", str(self.upstream), str(self.local))
        self.upstream_patch = patch.object(updater, "UPSTREAM", str(self.upstream))
        self.upstream_patch.start()
        self.addCleanup(self.upstream_patch.stop)

    def commit(self, message):
        updater.git(self.upstream, "add", ".")
        updater.git(self.upstream, "commit", "-m", message)

    def test_updates_to_official_main_and_is_idempotent(self):
        (self.upstream / "Dictionary/mm.binary").write_bytes(bytes(8))
        self.commit("New dictionary")
        new = updater.git(self.upstream, "rev-parse", "HEAD")
        self.assertEqual((self.old, new), updater.update(self.root))
        self.assertEqual((new, new), updater.update(self.root))

    def test_invalid_update_restores_previous_dictionary(self):
        (self.upstream / "Dictionary/mm.binary").write_bytes(b"x")
        self.commit("Incompatible dictionary")
        with self.assertRaises(ValueError):
            updater.update(self.root)
        self.assertEqual(self.old, updater.git(self.local, "rev-parse", "HEAD"))
        updater.validate(self.local)

    def test_keeps_local_changes(self):
        path = self.local / "Dictionary/mm.binary"
        path.write_bytes(b"local edit")
        with self.assertRaisesRegex(ValueError, "local dictionary changes"):
            updater.update(self.root)
        self.assertEqual(b"local edit", path.read_bytes())

    def test_fetch_failure_preserves_previous_dictionary(self):
        with patch.object(updater, "UPSTREAM", str(self.root / "missing")):
            with self.assertRaises(subprocess.CalledProcessError):
                updater.update(self.root)
        self.assertEqual(self.old, updater.git(self.local, "rev-parse", "HEAD"))


if __name__ == "__main__":
    unittest.main()
