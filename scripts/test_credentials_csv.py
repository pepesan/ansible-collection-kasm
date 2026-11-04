#!/usr/bin/env python3
"""Behavior tests for the credentials CSV writer."""
import csv
import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
HELPER_PATH = REPO / "roles" / "kasm_credentials" / "files" / "update_credentials_csv.py"
SPEC = importlib.util.spec_from_file_location("update_credentials_csv", HELPER_PATH)
CSV_HELPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CSV_HELPER)


LEGACY_COLUMNS = [
    "ip",
    "student_password",
    "kasm_url",
    "kasm_admin_user",
    "kasm_admin_password",
    "kasm_user_user",
    "kasm_user_password",
]


def row(url, ip, name):
    return {
        "kasm_url": url,
        "ip": ip,
        "nombre": name,
        "student_user": "student",
        "student_password": "student-pass",
        "kasm_admin_user": "admin@kasm.local",
        "kasm_admin_password": "admin-pass",
        "kasm_normal_user": "user@kasm.local",
        "kasm_normal_user_password": "normal-pass",
    }


class CredentialsCsvTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.csv_path = Path(self.temp_dir.name) / "access.csv"

    def tearDown(self):
        self.temp_dir.cleanup()

    def read_rows(self):
        with self.csv_path.open(newline="") as stream:
            reader = csv.DictReader(stream)
            return reader.fieldnames, list(reader)

    def test_schema_starts_with_url_and_rows_are_sorted_by_url(self):
        node10 = row("https://node10.example.test", "192.0.2.10", "node10")
        node2 = row("https://node2.example.test", "192.0.2.2", "node2")
        self.assertTrue(CSV_HELPER.update_row(str(self.csv_path), node10["ip"], node10["nombre"], node10))
        self.assertTrue(CSV_HELPER.update_row(str(self.csv_path), node2["ip"], node2["nombre"], node2))

        columns, rows = self.read_rows()
        self.assertEqual(
            columns,
            [
                "kasm_url",
                "ip",
                "student_user",
                "nombre",
                "student_password",
                "kasm_admin_user",
                "kasm_admin_password",
                "kasm_normal_user",
                "kasm_normal_user_password",
            ],
        )
        self.assertEqual(
            [item["kasm_url"] for item in rows],
            ["https://node10.example.test", "https://node2.example.test"],
        )


    def test_cli_writes_username_columns_and_passwords_from_environment(self):
        env = os.environ.copy()
        env.update({
            "STUDENT_PASSWORD": "student-pass",
            "KASM_ADMIN_PASSWORD": "admin-pass",
            "KASM_USER_PASSWORD": "normal-pass",
        })
        result = subprocess.run(
            [
                sys.executable,
                str(HELPER_PATH),
                "--csv-dir",
                str(self.csv_path.parent),
                "--csv-name",
                self.csv_path.name,
                "--ip",
                "192.0.2.20",
                "--name",
                "node20",
                "--student-user",
                "student",
                "--kasm-url",
                "https://node20.example.test",
                "--kasm-admin-user",
                "admin@kasm.local",
                "--kasm-normal-user",
                "user@kasm.local",
            ],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        columns, rows = self.read_rows()
        self.assertEqual(columns, CSV_HELPER.COLUMNS)
        self.assertEqual(
            rows,
            [row("https://node20.example.test", "192.0.2.20", "node20")],
        )
        self.assertEqual(self.csv_path.stat().st_mode & 0o777, 0o600)


    def test_legacy_schema_migrates_and_alias_ip_duplicates_collapse(self):
        legacy_rows = [
            {
                "ip": "192.0.2.2",
                "student_password": "old-student",
                "kasm_url": "https://node2.example.test",
                "kasm_admin_user": "admin@kasm.local",
                "kasm_admin_password": "old-admin",
                "kasm_user_user": "user@kasm.local",
                "kasm_user_password": "old-normal",
            },
            {
                "ip": "node2",
                "student_password": "old-student",
                "kasm_url": "https://node2.example.test",
                "kasm_admin_user": "admin@kasm.local",
                "kasm_admin_password": "old-admin",
                "kasm_user_user": "user@kasm.local",
                "kasm_user_password": "old-normal",
            },
            {
                "ip": "192.0.2.10",
                "student_password": "legacy-student",
                "kasm_url": "https://node10.example.test",
                "kasm_admin_user": "admin@kasm.local",
                "kasm_admin_password": "legacy-admin",
                "kasm_user_user": "legacy-user@kasm.local",
                "kasm_user_password": "legacy-normal",
            },
        ]
        with self.csv_path.open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=LEGACY_COLUMNS)
            writer.writeheader()
            writer.writerows(legacy_rows)

        current = row("https://node2.example.test", "192.0.2.2", "node2")
        self.assertTrue(CSV_HELPER.update_row(str(self.csv_path), current["ip"], current["nombre"], current))

        columns, rows = self.read_rows()
        self.assertEqual(columns, CSV_HELPER.COLUMNS)
        self.assertEqual(len(rows), 2)
        node2 = next(item for item in rows if item["nombre"] == "node2")
        node10 = next(item for item in rows if item["kasm_url"].endswith("node10.example.test"))
        self.assertEqual(node2, current)
        self.assertEqual(node10["kasm_normal_user"], "legacy-user@kasm.local")
        self.assertEqual(node10["kasm_normal_user_password"], "legacy-normal")

    def test_upsert_matches_either_identity_and_is_idempotent(self):
        first = row("https://node2.example.test", "192.0.2.2", "node2")
        CSV_HELPER.update_row(str(self.csv_path), first["ip"], first["nombre"], first)

        changed_ip = row("https://node2.example.test", "192.0.2.22", "node2")
        self.assertTrue(CSV_HELPER.update_row(str(self.csv_path), changed_ip["ip"], changed_ip["nombre"], changed_ip))
        columns, rows = self.read_rows()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["ip"], "192.0.2.22")

        renamed = row("https://node2.example.test", "192.0.2.22", "node-renamed")
        self.assertTrue(CSV_HELPER.update_row(str(self.csv_path), renamed["ip"], renamed["nombre"], renamed))
        self.assertFalse(CSV_HELPER.update_row(str(self.csv_path), renamed["ip"], renamed["nombre"], renamed))
        _, rows = self.read_rows()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["nombre"], "node-renamed")


if __name__ == "__main__":
    unittest.main()
