import base64
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from android_signing import ENCRYPTED_SECRET_NAME, SECRET_NAMES, prepare, verify_apk_report


class SigningFixture(unittest.TestCase):
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


class AndroidSigningTest(SigningFixture):
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


@unittest.skipUnless(shutil.which("gpg"), "GPG is needed for encrypted signing tests")
class EncryptedAndroidSigningTest(SigningFixture):
    def encrypted_key(self):
        signing = self.root / "signing"
        signing.mkdir(exist_ok=True)
        (signing / "android-release.cer").write_bytes(b"public certificate")
        plaintext = self.root / "fixture-key"
        plaintext.write_bytes(b"existing private release key")
        with tempfile.TemporaryDirectory() as home:
            subprocess.run([
                "gpg", "--no-options", "--homedir", home, "--batch", "--yes",
                "--pinentry-mode", "loopback", "--no-symkey-cache", "--passphrase-fd", "0",
                "--symmetric", "--cipher-algo", "AES256",
                "--output", str(signing / "android-release.jks.gpg"), str(plaintext),
            ], input=b"test-only-long-passphrase\n", capture_output=True, check=True)
        plaintext.unlink()
        self.env[ENCRYPTED_SECRET_NAME] = "test-only-long-passphrase"
        return signing / "android-release.jks.gpg"

    def test_encrypted_key_is_restored_outside_workspace_with_pinned_certificate(self):
        self.encrypted_key()
        prepare(self.env)
        key = self.root / "keynako-release.jks"
        self.assertEqual(key.read_bytes(), b"existing private release key")
        self.assertEqual(key.stat().st_mode & 0o777, 0o600)
        self.assertEqual(Path(self.env["GITHUB_OUTPUT"]).read_text(), "kind=encrypted\n")
        exported = Path(self.env["GITHUB_ENV"]).read_text()
        self.assertIn("KEYNAKO_KEY_ALIAS=keynako-release\n", exported)
        self.assertIn(hashlib.sha256(b"public certificate").hexdigest(), exported)
        self.assertFalse(list(self.root.glob("keynako-gnupg-*")))

    def test_bad_passphrase_cannot_fall_back_to_cache_and_leaves_no_decrypted_key(self):
        self.cached_key()
        self.encrypted_key()
        self.env[ENCRYPTED_SECRET_NAME] = "wrong-password"
        with self.assertRaisesRegex(ValueError, "Could not decrypt"):
            prepare(self.env)
        self.assertFalse((self.root / "keynako-release.jks").exists())
        self.assertFalse(Path(self.env["GITHUB_ENV"]).exists())

    def test_corrupt_ciphertext_is_rejected_without_exporting_credentials(self):
        self.encrypted_key().write_bytes(b"damaged encrypted file")
        with self.assertRaisesRegex(ValueError, "Could not decrypt"):
            prepare(self.env)
        self.assertFalse((self.root / "keynako-release.jks").exists())
        self.assertFalse(Path(self.env["GITHUB_ENV"]).exists())

    def test_missing_committed_files_fail_even_with_cached_key(self):
        self.cached_key()
        self.env[ENCRYPTED_SECRET_NAME] = "test-only-long-passphrase"
        with self.assertRaisesRegex(ValueError, "must both be committed"):
            prepare(self.env)

    def test_legacy_and_encrypted_secrets_cannot_select_different_signers_silently(self):
        self.encrypted_key()
        self.release_secrets()
        with self.assertRaisesRegex(ValueError, "not both"):
            prepare(self.env)

    def test_pull_requests_never_decrypt_the_release_key(self):
        self.cached_key()
        self.encrypted_key()
        self.env["GITHUB_EVENT_NAME"] = "pull_request"
        prepare(self.env)
        self.assertEqual(Path(self.env["GITHUB_OUTPUT"]).read_text(), "kind=ci\n")
        self.assertFalse((self.root / "keynako-release.jks").exists())
        self.assertNotIn("test-only-long-passphrase", Path(self.env["GITHUB_ENV"]).read_text())

    def test_required_release_signing_fails_when_secret_is_missing(self):
        self.cached_key()
        self.env["KEYNAKO_REQUIRE_ENCRYPTED"] = "true"
        with self.assertRaisesRegex(ValueError, "Set KEYNAKO_ANDROID_SIGNING_PASSPHRASE"):
            prepare(self.env)

    def test_passphrase_cannot_inject_github_environment_variables(self):
        self.encrypted_key()
        self.env[ENCRYPTED_SECRET_NAME] += "\nEXTRA=value"
        with self.assertRaisesRegex(ValueError, "single-line"):
            prepare(self.env)
        self.assertFalse((self.root / "keynako-release.jks").exists())


class ApkSignerVerificationTest(unittest.TestCase):
    def test_expected_signer_is_required_for_all_reported_signature_versions(self):
        with tempfile.TemporaryDirectory() as temp:
            report = Path(temp) / "report.txt"
            expected = "a" * 64
            environ = {"KEYNAKO_EXPECTED_CERTIFICATE_SHA256": expected}
            report.write_text(f"V2 Signer: certificate SHA-256 digest: {expected}\n")
            verify_apk_report(report, environ)
            for contents in ("", "Signer: certificate SHA-256 digest: " + "b" * 64,
                             report.read_text() + "Other certificate SHA-256 digest: " + "b" * 64):
                with self.subTest(contents=contents):
                    report.write_text(contents)
                    with self.assertRaisesRegex(ValueError, "does not match"):
                        verify_apk_report(report, environ)


if __name__ == "__main__":
    unittest.main()
