"""EST-04: unit tests of the cluster-access / user-access CSV writers (no network, no Ansible).

Run: python3 -m unittest scripts/test_cluster_csv.py
"""
import csv
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

FILES = Path(__file__).resolve().parents[1] / "roles" / "kasm_credentials" / "files"
CLUSTER_SCRIPT = FILES / "update_cluster_csv.py"
USER_SCRIPT = FILES / "update_user_csv.py"

CLUSTER = ["role", "node", "fqdn", "ip", "ssh_user", "ssh_password", "kasm_url", "kasm_admin_user",
           "kasm_admin_password", "kasm_manager_token", "kasm_version"]
USER = ["kasm_url", "kasm_user", "kasm_user_password", "kasm_group", "workspaces"]

TOKEN = "TokenSecretValueAlpha"
ADMIN = "AdminSecretValueBravo"
SSH = "SshSecretValueCharlie"
ALICE = "AlicePassSecretDelta"
BOB = "BobPassSecretEcho"


def load_module():
    spec = importlib.util.spec_from_file_location("update_cluster_csv", CLUSTER_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CsvTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.csv_dir = self.root / "csv"
        self.creds = self.root / ".credentials"
        self.creds.mkdir(mode=0o700)
        (self.creds / "mgr.example.com-manager-token.pass").write_text(TOKEN + "\n")
        self.argv_seen = []

    def run_script(self, script, kind, row=None, env=None, extra=(), check=True):
        argv = [sys.executable, str(script), "--csv-dir", str(self.csv_dir),
                "--credentials-dir", str(self.creds), "--project", "Demo Course"]
        if script == CLUSTER_SCRIPT:
            argv += ["--kind", kind]
        argv += list(extra)
        self.argv_seen.append(argv)
        proc_env = {**os.environ, **(env or {})}
        return subprocess.run(argv, input=json.dumps(row) if row is not None else "", text=True,
                              capture_output=True, env=proc_env, check=check)

    def manager(self, node="mgr", **env):
        return self.run_script(
            CLUSTER_SCRIPT, "cluster",
            {"role": "manager", "node": node, "fqdn": "mgr.example.com", "ip": "192.0.2.10", "ssh_user": "root",
             "kasm_url": "https://mgr.example.com", "kasm_admin_user": "admin@kasm.local", "kasm_version": "1.19.0",
             "secret_files": {"kasm_admin_password": "mgr-admin.pass", "kasm_manager_token": "mgr.example.com-manager-token.pass",
                              "ssh_password": "mgr-ssh.pass"}},
            env={"KASM_CSV_KASM_ADMIN_PASSWORD": ADMIN, **env})

    def agent(self, node):
        return self.run_script(
            CLUSTER_SCRIPT, "cluster",
            {"role": "agent", "node": node, "fqdn": node + ".example.com", "ip": "198.51.100.5", "ssh_user": "root",
             "kasm_url": "https://mgr.example.com", "kasm_version": "1.19.0",
             "secret_files": {"ssh_password": node + "-ssh.pass"}})

    def user(self, name, password, group="students", workspaces="Core Ubuntu;Other"):
        return self.run_script(
            USER_SCRIPT, "user",
            {"kasm_url": "https://mgr.example.com", "kasm_user": name, "kasm_group": group, "workspaces": workspaces,
             "secret_files": {"kasm_user_password": f"mgr-kasm-user-{name}.pass"}},
            env={"KASM_CSV_KASM_USER_PASSWORD": password})

    def rows(self, name):
        with (self.csv_dir / name).open(newline="") as stream:
            reader = csv.DictReader(stream)
            return reader.fieldnames, list(reader)

    def test_cluster_columns_order_upsert_and_mode(self):
        self.agent("agent-02")
        self.manager()
        self.agent("agent-01")
        self.agent("agent-02")  # same node again: replaced, not duplicated
        path = self.csv_dir / "cluster-access-demo-course.csv"
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        fields, rows = self.rows(path.name)
        self.assertEqual(fields, CLUSTER)
        self.assertEqual([r["node"] for r in rows], ["agent-01", "agent-02", "mgr"])
        manager = rows[2]
        self.assertEqual((manager["kasm_admin_password"], manager["kasm_manager_token"]), (ADMIN, TOKEN))
        self.assertEqual(rows[0]["kasm_admin_password"], "")
        self.assertEqual(rows[0]["kasm_manager_token"], "")

    def test_upsert_changes_value_and_reports_changed(self):
        self.assertIn("changed", self.manager().stdout)
        self.assertEqual(self.manager().stdout.strip(), "csv: unchanged")
        self.manager(KASM_CSV_KASM_ADMIN_PASSWORD="RotatedAdmin999")
        _, rows = self.rows("cluster-access-demo-course.csv")
        self.assertEqual([r["kasm_admin_password"] for r in rows], ["RotatedAdmin999"])

    def test_user_csv_columns_and_no_operator_data(self):
        self.user("bob", BOB)
        self.user("alice", ALICE)
        self.user("bob", BOB, group="teachers")
        fields, rows = self.rows("user-access-demo-course.csv")
        self.assertEqual(fields, USER)
        self.assertEqual([r["kasm_user"] for r in rows], ["alice", "bob"])
        self.assertEqual(rows[1]["kasm_group"], "teachers")
        self.assertEqual(rows[0]["workspaces"], "Core Ubuntu;Other")
        self.assertEqual((self.csv_dir / "user-access-demo-course.csv").stat().st_mode & 0o777, 0o600)
        forbidden = {"ip", "fqdn", "ssh_user", "ssh_password", "kasm_admin_user", "kasm_admin_password",
                     "kasm_manager_token", "role", "node"}
        self.assertFalse(forbidden & set(fields))
        text = (self.csv_dir / "user-access-demo-course.csv").read_text()
        for secret in (ADMIN, TOKEN, SSH):
            self.assertNotIn(secret, text)

    def test_regenerate_from_credentials_is_byte_identical(self):
        self.manager(KASM_CSV_SSH_PASSWORD=SSH)
        self.agent("agent-01")
        self.user("alice", ALICE)
        self.user("bob", BOB)
        paths = [self.csv_dir / "cluster-access-demo-course.csv", self.csv_dir / "user-access-demo-course.csv"]
        before = [p.read_bytes() for p in paths]
        for p in paths:
            p.unlink()
        self.run_script(CLUSTER_SCRIPT, "cluster", extra=["--from-credentials"])
        self.run_script(USER_SCRIPT, "user", extra=["--from-credentials"])
        self.assertEqual([p.read_bytes() for p in paths], before)
        self.assertEqual([p.stat().st_mode & 0o777 for p in paths], [0o600, 0o600])
        self.assertIn(SSH, before[0].decode())

    def test_secrets_never_in_argv_stdin_or_metadata(self):
        self.manager(KASM_CSV_SSH_PASSWORD=SSH)
        self.user("alice", ALICE)
        secrets = (TOKEN, ADMIN, SSH, ALICE)
        for argv in self.argv_seen:
            for secret in secrets:
                self.assertFalse(any(secret in part for part in argv))
        meta = (self.creds / "cluster-meta.json").read_text()
        for secret in secrets:
            self.assertNotIn(secret, meta)
        self.assertEqual((self.creds / "cluster-meta.json").stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.creds / "mgr-ssh.pass").read_text().strip(), SSH)
        self.assertEqual((self.creds / "mgr-ssh.pass").stat().st_mode & 0o777, 0o600)
        for option in ("--password", "--token", "--admin-password", "--user-password", "--ssh-password"):
            bad = self.run_script(CLUSTER_SCRIPT, "cluster", extra=[option, "x"], check=False)
            self.assertNotEqual(bad.returncode, 0)
        leaking = self.run_script(CLUSTER_SCRIPT, "cluster", {"node": "n", "kasm_manager_token": "x"}, check=False)
        self.assertNotEqual(leaking.returncode, 0)

    def test_missing_required_secret_fails_without_touching_files(self):
        self.manager()
        before = (self.csv_dir / "cluster-access-demo-course.csv").read_bytes()
        meta = (self.creds / "cluster-meta.json").read_bytes()
        (self.creds / "mgr-admin.pass").unlink()
        # an upsert of another node must fail loudly rather than write the manager row empty
        bad = self.run_script(CLUSTER_SCRIPT, "cluster",
                              {"role": "agent", "node": "agent-09", "secret_files": {}}, check=False)
        self.assertNotEqual(bad.returncode, 0)
        self.assertIn("kasm_admin_password", bad.stderr)
        self.assertEqual((self.csv_dir / "cluster-access-demo-course.csv").read_bytes(), before)
        self.assertEqual((self.creds / "cluster-meta.json").read_bytes(), meta)

    def test_failed_replace_keeps_previous_csv_and_leaves_no_temp_files(self):
        self.manager()
        path = self.csv_dir / "cluster-access-demo-course.csv"
        before = path.read_bytes()
        module = load_module()
        with mock.patch.object(os, "replace", side_effect=OSError("injected")):
            with self.assertRaises(OSError):
                module.write_atomic(str(path), b"half,written\n")
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual([p.name for p in self.csv_dir.iterdir()], [path.name])


if __name__ == "__main__":
    unittest.main()
