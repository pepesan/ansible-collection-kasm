#!/usr/bin/env python3
"""Behavior tests for the collection version bump script."""
import importlib.util
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch


SCRIPT_PATH = Path(__file__).resolve().with_name("bump_version.py")
SPEC = importlib.util.spec_from_file_location("bump_version", SCRIPT_PATH)
BUMP_VERSION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUMP_VERSION)


class BumpVersionTests(unittest.TestCase):
    def test_semver_components_increment_and_reset_lower_components(self):
        self.assertEqual(BUMP_VERSION.increment_version("0.0.1", "patch"), "0.0.2")
        self.assertEqual(BUMP_VERSION.increment_version("0.0.1", "minor"), "0.1.0")
        self.assertEqual(BUMP_VERSION.increment_version("0.0.1", "major"), "1.0.0")
        self.assertEqual(BUMP_VERSION.increment_version("2.4.9", "minor"), "2.5.0")
        self.assertEqual(BUMP_VERSION.increment_version("2.4.9", "major"), "3.0.0")

    def test_cli_updates_the_repository_version_and_reports_result(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "galaxy.yml"
            path.write_text("namespace: pepesan\nversion: 0.0.1\n", encoding="utf-8")
            output = io.StringIO()

            with (
                patch.object(BUMP_VERSION, "REPO", Path(temp_dir)),
                patch.object(sys, "argv", ["bump_version.py", "patch"]),
                redirect_stdout(output),
            ):
                BUMP_VERSION.main()

            self.assertEqual(path.read_text(encoding="utf-8"), "namespace: pepesan\nversion: 0.0.2\n")
            self.assertEqual(output.getvalue(), "galaxy.yml: 0.0.1 -> 0.0.2 (patch)\n")

    def test_file_bump_changes_only_the_version_value(self):
        original = "namespace: pepesan\nname: kasm\nversion: 0.0.1\nreadme: README.md\n"
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "galaxy.yml"
            path.write_text(original, encoding="utf-8")

            old, new = BUMP_VERSION.bump_file(path, "patch")

            self.assertEqual((old, new), ("0.0.1", "0.0.2"))
            self.assertEqual(
                path.read_text(encoding="utf-8"),
                original.replace("version: 0.0.1", "version: 0.0.2"),
            )

    def test_invalid_semver_is_rejected_without_writing(self):
        original = "namespace: pepesan\nname: kasm\nversion: 01.0.1\n"
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "galaxy.yml"
            path.write_text(original, encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "not a SemVer version"):
                BUMP_VERSION.bump_file(path, "patch")

            self.assertEqual(path.read_text(encoding="utf-8"), original)

    def test_duplicate_version_lines_are_rejected_without_writing(self):
        original = "version: 0.0.1\nversion: 0.0.2\n"
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "galaxy.yml"
            path.write_text(original, encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "exactly one SemVer version line"):
                BUMP_VERSION.bump_file(path, "patch")

            self.assertEqual(path.read_text(encoding="utf-8"), original)


if __name__ == "__main__":
    unittest.main()
