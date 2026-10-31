"""Validate, or update and validate, the pinned official azooKey dictionary."""

import argparse
from pathlib import Path
import subprocess


SUBMODULE = "third_party/azookey_dictionary_storage"
UPSTREAM = "https://github.com/azooKey/azooKey_dictionary_storage.git"


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(root), *args], text=True
    ).strip()


def validate(dictionary_repo: Path) -> None:
    """Check the files and binary layouts consumed by the Kotlin/C++ readers."""
    license_text = (dictionary_repo / "LICENSE").read_text(encoding="utf-8")
    if "Apache License" not in license_text or "Version 2.0" not in license_text:
        raise ValueError("The official dictionary must retain its Apache-2.0 license")

    root = dictionary_repo / "Dictionary"

    def binary(relative: str, alignment: int = 1) -> bytes:
        data = (root / relative).read_bytes()
        if not data or len(data) % alignment:
            raise ValueError(f"Empty or incompatible dictionary file: {relative}")
        return data

    characters = binary("louds/charID.chid").decode("utf-8")
    if len(characters) > 256 or len(set(characters)) != len(characters):
        raise ValueError("The LOUDS character table must contain unique byte-sized IDs")
    binary("mm.binary", 4)
    # The current readers use 1,319 connection IDs and 8-byte score records.
    for cid in range(1319):
        binary(f"cb/{cid}.binary", 8)
    shards = sorted((root / "louds").glob("*.louds"))
    if not shards:
        raise ValueError("No LOUDS dictionary shards found")
    for shard in shards:
        binary(f"louds/{shard.name}", 8)
        binary(f"louds/{shard.stem}.loudschars2")
        binary(f"louds/{shard.stem}0.loudstxt3")


def update(root: Path) -> tuple[str, str]:
    """Fetch only the official main ref; restore the old pin on invalid data."""
    path = root / SUBMODULE
    if git(path, "status", "--porcelain"):
        raise ValueError("Refusing to overwrite local dictionary changes")
    old = git(path, "rev-parse", "HEAD")
    # Do not trust a locally overridden submodule origin or tracking branch.
    git(path, "fetch", "--depth=1", UPSTREAM, "refs/heads/main")
    new = git(path, "rev-parse", "FETCH_HEAD")
    git(path, "checkout", "--detach", new)
    try:
        validate(path)
    except Exception:
        git(path, "checkout", "--detach", old)
        raise
    return old, new


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--update", action="store_true", help="Fetch official main before validation"
    )
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.update:
        old, new = update(root)
        print(f"azooKey dictionary: {old} -> {new}")
        print("Dictionary updated" if old != new else "Already up to date")
    else:
        validate(root / SUBMODULE)
        print("azooKey dictionary validated")


if __name__ == "__main__":
    main()
