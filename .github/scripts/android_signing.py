"""Select an existing Android signer without silently replacing its identity."""

import base64
import binascii
import os
from pathlib import Path


SECRET_NAMES = (
    "KEYNAKO_ANDROID_KEYSTORE_BASE64",
    "KEYNAKO_ANDROID_STORE_PASSWORD",
    "KEYNAKO_ANDROID_KEY_ALIAS",
    "KEYNAKO_ANDROID_KEY_PASSWORD",
)


def prepare(environ):
    # Never decode or export a release key during a pull-request build.
    values = [environ.get(name, "") for name in SECRET_NAMES]
    if environ.get("GITHUB_EVENT_NAME") == "pull_request":
        values = [""] * len(SECRET_NAMES)

    if any(values):
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
        keystore = Path(environ["GITHUB_WORKSPACE"]) / ".ci/keynako-ci-release.jks"
        if not keystore.is_file() or keystore.stat().st_size == 0:
            raise ValueError(
                "The existing Android CI signing key is unavailable. Refusing to generate "
                "a replacement: it would break updates of installed APKs. Restore the original "
                "keystore or configure the four KEYNAKO_ANDROID_* secrets with that key. "
                "See docs/github_actions_builds.md."
            )
        store_password = key_password = "keynako-ci-release-v1"
        alias = "keynako-ci"
        kind = "ci"

    exported = {
        "KEYNAKO_KEYSTORE_PATH": str(keystore),
        "KEYNAKO_STORE_PASSWORD": store_password,
        "KEYNAKO_KEY_ALIAS": alias,
        "KEYNAKO_KEY_PASSWORD": key_password,
    }
    if any("\n" in value or "\r" in value for value in exported.values()):
        raise ValueError("Android signing paths, alias and passwords must be single-line values.")

    if kind == "release":
        # Keep the private key outside the workspace, cache, and uploaded artifacts.
        with keystore.open("wb") as stream:
            keystore.chmod(0o600)
            stream.write(contents)

    with Path(environ["GITHUB_ENV"]).open("a") as stream:
        stream.writelines(f"{name}={value}\n" for name, value in exported.items())
    with Path(environ["GITHUB_OUTPUT"]).open("a") as stream:
        stream.write(f"kind={kind}\n")


if __name__ == "__main__":
    try:
        prepare(os.environ)
    except ValueError as error:
        raise SystemExit(str(error)) from None

