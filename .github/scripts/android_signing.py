"""Select an existing Android signer without silently replacing its identity."""

import base64
import binascii
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


SECRET_NAMES = (
    "KEYNAKO_ANDROID_KEYSTORE_BASE64",
    "KEYNAKO_ANDROID_STORE_PASSWORD",
    "KEYNAKO_ANDROID_KEY_ALIAS",
    "KEYNAKO_ANDROID_KEY_PASSWORD",
)
ENCRYPTED_SECRET_NAME = "KEYNAKO_ANDROID_SIGNING_PASSPHRASE"
ENCRYPTED_KEY_ALIAS = "keynako-release"


def decrypt_keystore(encrypted, destination, password, runner_temp):
    try:
        with tempfile.TemporaryDirectory(prefix="keynako-gnupg-", dir=runner_temp) as home:
            with destination.open("wb") as output:
                destination.chmod(0o600)
                result = subprocess.run(
                    [
                        "gpg", "--no-options", "--homedir", home, "--batch",
                        "--pinentry-mode", "loopback", "--no-symkey-cache",
                        "--passphrase-fd", "0", "--decrypt", str(encrypted),
                    ],
                    input=(password + "\n").encode(),
                    stdout=output,
                    stderr=subprocess.PIPE,
                    check=False,
                )
        if result.returncode or destination.stat().st_size == 0:
            raise ValueError("Could not decrypt the Android release keystore. Check the signing secret.")
    except (OSError, ValueError) as error:
        destination.unlink(missing_ok=True)
        if isinstance(error, ValueError):
            raise
        raise ValueError("Could not run GPG to restore the Android release keystore.") from None


def verify_apk_report(path, environ):
    expected = environ.get("KEYNAKO_EXPECTED_CERTIFICATE_SHA256", "")
    if not expected:
        return
    digests = set(re.findall(r"certificate SHA-256 digest:\s*([0-9a-fA-F]{64})\b", Path(path).read_text()))
    if {digest.lower() for digest in digests} != {expected.lower()}:
        raise ValueError("The APK signer does not match the committed Android release certificate.")


def prepare(environ):
    # Pull requests validate an unsigned build and must never publish another signer.
    if environ.get("GITHUB_EVENT_NAME") == "pull_request":
        raise ValueError("Pull requests must not sign Android APKs. Build an unsigned release for validation.")
    values = [environ.get(name, "") for name in SECRET_NAMES]
    password = environ.get(ENCRYPTED_SECRET_NAME, "")

    if environ.get("KEYNAKO_REQUIRE_ENCRYPTED", "").lower() == "true" and not password:
        raise ValueError("Set KEYNAKO_ANDROID_SIGNING_PASSPHRASE to build with the encrypted release key.")

    expected_certificate = ""
    if password:
        if any(values):
            raise ValueError("Configure either the encrypted signing secret or the four legacy secrets, not both.")
        if "\n" in password or "\r" in password:
            raise ValueError("The Android signing passphrase must be a single-line value.")
        signing = Path(environ["GITHUB_WORKSPACE"]) / "signing"
        encrypted = signing / "android-release.jks.gpg"
        certificate = signing / "android-release.cer"
        if not encrypted.is_file() or not certificate.is_file():
            raise ValueError("The encrypted Android keystore and public certificate must both be committed.")
        expected_certificate = hashlib.sha256(certificate.read_bytes()).hexdigest()
        keystore = Path(environ["RUNNER_TEMP"]) / "keynako-release.jks"
        store_password = key_password = password
        alias = ENCRYPTED_KEY_ALIAS
        kind = "encrypted"
    elif any(values):
        if not all(values):
            raise ValueError("Android release signing requires all four KEYNAKO_ANDROID_* secrets.")
        encoded, store_password, alias, key_password = values
        try:
            contents = base64.b64decode("".join(encoded.split()), validate=True)
        except (binascii.Error, ValueError):
            raise ValueError("KEYNAKO_ANDROID_KEYSTORE_BASE64 is not valid Base64.") from None
        if not contents:
            raise ValueError("KEYNAKO_ANDROID_KEYSTORE_BASE64 contains an empty keystore.")
        keystore = Path(environ["RUNNER_TEMP"]) / "keynako-release.jks"
        kind = "release"
    else:
        raise ValueError(
            "No Android release signer is configured. Refusing to generate a replacement "
            "or reuse a cached CI key: it would break updates of installed APKs. "
            "Set KEYNAKO_ANDROID_SIGNING_PASSPHRASE for the committed encrypted release key. "
            "See docs/github_actions_builds.md."
        )

    exported = {
        "KEYNAKO_KEYSTORE_PATH": str(keystore),
        "KEYNAKO_STORE_PASSWORD": store_password,
        "KEYNAKO_KEY_ALIAS": alias,
        "KEYNAKO_KEY_PASSWORD": key_password,
        "KEYNAKO_EXPECTED_CERTIFICATE_SHA256": expected_certificate,
    }
    if any("\n" in value or "\r" in value for value in exported.values()):
        raise ValueError("Android signing paths, alias and passwords must be single-line values.")

    if kind == "release":
        # Keep the private key outside the workspace, cache, and uploaded artifacts.
        with keystore.open("wb") as stream:
            keystore.chmod(0o600)
            stream.write(contents)
    elif kind == "encrypted":
        decrypt_keystore(encrypted, keystore, password, environ["RUNNER_TEMP"])

    with Path(environ["GITHUB_ENV"]).open("a") as stream:
        stream.writelines(f"{name}={value}\n" for name, value in exported.items())
    with Path(environ["GITHUB_OUTPUT"]).open("a") as stream:
        stream.write(f"kind={kind}\n")


if __name__ == "__main__":
    try:
        if len(sys.argv) == 3 and sys.argv[1] == "--verify-apk-report":
            verify_apk_report(sys.argv[2], os.environ)
        elif len(sys.argv) == 1:
            prepare(os.environ)
        else:
            raise ValueError("Usage: android_signing.py [--verify-apk-report PATH]")
    except ValueError as error:
        raise SystemExit(str(error)) from None
