#!/usr/bin/env python3
"""Increment the collection version in galaxy.yml by a SemVer component."""
import argparse
import re
from pathlib import Path


SEMVER = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")
VERSION_LINE = re.compile(
    r"(?m)^(version:[ \t]*)([0-9]+\.[0-9]+\.[0-9]+)([ \t]*(?:#.*)?)$"
)
REPO = Path(__file__).resolve().parents[1]


def increment_version(version: str, component: str) -> str:
    match = SEMVER.fullmatch(version)
    if not match:
        raise ValueError(f"not a SemVer version: {version!r}")
    if component not in {"patch", "minor", "major"}:
        raise ValueError(f"unknown version component: {component!r}")

    major, minor, patch = (int(value) for value in match.groups())
    if component == "major":
        major, minor, patch = major + 1, 0, 0
    elif component == "minor":
        major, minor, patch = major, minor + 1, 0
    else:
        major, minor, patch = major, minor, patch + 1
    return f"{major}.{minor}.{patch}"


def bump_file(path: Path, component: str) -> tuple[str, str]:
    content = path.read_text(encoding="utf-8")
    matches = list(VERSION_LINE.finditer(content))
    if len(matches) != 1:
        raise ValueError(f"expected exactly one SemVer version line in {path}")

    match = matches[0]
    old_version = match.group(2)
    new_version = increment_version(old_version, component)
    updated = content[: match.start(2)] + new_version + content[match.end(2) :]
    path.write_text(updated, encoding="utf-8")
    return old_version, new_version


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("component", choices=("patch", "minor", "major"))
    args = parser.parse_args()

    try:
        old_version, new_version = bump_file(REPO / "galaxy.yml", args.component)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(f"galaxy.yml: {old_version} -> {new_version} ({args.component})")


if __name__ == "__main__":
    main()
