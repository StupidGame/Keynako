import base64
from pathlib import Path
import tempfile
import unittest

from android_signing import SECRET_NAMES, prepare


class AndroidSigningTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = {
            "GITHUB_WORKSPACE": str(self.root),
            "RUNNER_TEMP": str(self.root),
            "GITHUB_EVENT_NAME": "workflow_dispatch",
            "GITHUB_ENV": str(self.root / "env"),
            "GITHUB_OUTPUT": str(self.root / "output"),
        }

    def cached_key(self):
        path = self.root / ".ci/keynako-ci-release.jks"
        path.parent.mkdir()
        path.write_bytes(b"existing cached key")
        return path

    def release_secrets(self):
        self.env.update(zip(SECRET_NAMES, (
            base64.b64encode(b"existing private release key").decode(),
            "store-password", "release-alias", "key-password",
        )))

    def test_cache_miss_fails_without_creating_a_key_or_exporting_credentials(self):
        with self.assertRaisesRegex(ValueError, "Refusing to generate"):
            prepare(self.env)
        self.assertFalse((self.root / ".ci").exists())
        self.assertFalse(Path(self.env["GITHUB_ENV"]).exists())

    def test_existing_cached_key_is_reused_unchanged(self):
        key = self.cached_key()
        prepare(self.env)
        self.assertEqual(key.read_bytes(), b"existing cached key")
        self.assertIn(str(key), Path(self.env["GITHUB_ENV"]).read_text())
        self.assertEqual(Path(self.env["GITHUB_OUTPUT"]).read_text(), "kind=ci\n")

    def test_empty_cached_key_fails(self):
        self.cached_key().write_bytes(b"")
        with self.assertRaisesRegex(ValueError, "Refusing to generate"):
            prepare(self.env)

    def test_release_secret_takes_precedence_and_does_not_modify_the_cache(self):
        cache = self.cached_key()
        self.release_secrets()
        prepare(self.env)
        key = self.root / "keynako-release.jks"
        self.assertEqual(key.read_bytes(), b"existing private release key")
        self.assertEqual(key.stat().st_mode & 0o777, 0o600)
        self.assertEqual(cache.read_bytes(), b"existing cached key")
        self.assertIn("KEYNAKO_KEY_ALIAS=release-alias\n", Path(self.env["GITHUB_ENV"]).read_text())
        self.assertEqual(Path(self.env["GITHUB_OUTPUT"]).read_text(), "kind=release\n")

    def test_partial_release_secrets_fail_instead_of_falling_back_to_the_cache(self):
        self.cached_key()
        self.env[SECRET_NAMES[0]] = "configured"
        with self.assertRaisesRegex(ValueError, "all four"):
            prepare(self.env)
        self.assertFalse(Path(self.env["GITHUB_ENV"]).exists())

    def test_malformed_or_empty_base64_fails_without_exporting_credentials(self):
        for encoded in ("not-base64!", "   "):
            with self.subTest(encoded=encoded):
                self.release_secrets()
                self.env[SECRET_NAMES[0]] = encoded
                with self.assertRaises(ValueError):
                    prepare(self.env)
                self.assertFalse((self.root / "keynako-release.jks").exists())
                self.assertFalse(Path(self.env["GITHUB_ENV"]).exists())

    def test_pull_request_never_decodes_or_exports_release_secrets(self):
        cache = self.cached_key()
        self.release_secrets()
        self.env["GITHUB_EVENT_NAME"] = "pull_request"
        prepare(self.env)
        exported = Path(self.env["GITHUB_ENV"]).read_text()
        self.assertIn(str(cache), exported)
        self.assertNotIn("release-alias", exported)
        self.assertFalse((self.root / "keynako-release.jks").exists())

    def test_pull_request_without_cached_key_cannot_fall_back_to_release_secrets(self):
        self.release_secrets()
        self.env["GITHUB_EVENT_NAME"] = "pull_request"
        with self.assertRaisesRegex(ValueError, "Refusing to generate"):
            prepare(self.env)
        self.assertFalse((self.root / "keynako-release.jks").exists())

    def test_newline_in_credentials_cannot_inject_github_environment_values(self):
        self.release_secrets()
        self.env[SECRET_NAMES[1]] = "password\nEXTRA=value"
        with self.assertRaisesRegex(ValueError, "single-line"):
            prepare(self.env)
        self.assertFalse((self.root / "keynako-release.jks").exists())
        self.assertFalse(Path(self.env["GITHUB_ENV"]).exists())


if __name__ == "__main__":
    unittest.main()
