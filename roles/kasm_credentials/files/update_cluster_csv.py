#!/usr/bin/env python3
"""Writes the cluster-access-<project>.csv and user-access-<project>.csv files.

Runs on the Ansible control node (delegate_to: localhost). Design:

* The CSV is always rendered from two sources: non-secret metadata of every
  row (<credentials-dir>/cluster-meta.json) and the secrets, one file each in
  <credentials-dir> (mode 600, the same *.pass files the roles already create).
  So the CSV can be regenerated at any time without touching the nodes:
  --from-credentials re-renders it and gives the same bytes.
* Upsert (default): one row as JSON on stdin (no secrets, plus "secret_files":
  {column: file name in the credentials dir}). A secret may be passed in the
  environment as KASM_CSV_<COLUMN> (e.g. KASM_CSV_SSH_PASSWORD); it is stored
  in its secret file when that differs. Secrets are never accepted on the
  command line or on stdin, so they do not show up in the process list.
* One flock covers the whole read-modify-write cycle; files are written to a
  temporary file in the same directory and moved with os.replace(), so a
  failure never leaves a half-written CSV or metadata file. Mode is 600.

Prints "csv: changed" or "csv: unchanged" (used for changed_when).
"""
import argparse
import csv
import fcntl
import io
import json
import os
import re
import sys
import tempfile

KINDS = {
    "cluster": {
        "prefix": "cluster-access",
        "section": "nodes",
        "key": "node",
        "columns": [
            "role", "node", "fqdn", "ip", "ssh_user", "ssh_password", "kasm_url",
            "kasm_admin_user", "kasm_admin_password", "kasm_manager_token", "kasm_version",
        ],
        "secrets": ["ssh_password", "kasm_admin_password", "kasm_manager_token"],
    },
    "user": {
        "prefix": "user-access",
        "section": "users",
        "key": "kasm_user",
        "columns": ["kasm_url", "kasm_user", "kasm_user_password", "kasm_group", "workspaces"],
        "secrets": ["kasm_user_password"],
    },
}
META_NAME = "cluster-meta.json"


def required_secrets(kind, row):
    """Secrets without which a row is useless: fail loudly instead of writing it empty."""
    if kind == "user":
        return ["kasm_user_password"]
    return ["kasm_admin_password", "kasm_manager_token"] if row.get("role") == "manager" else []


def slug(project):
    return re.sub(r"[^A-Za-z0-9._-]+", "-", (project or "").lower()).strip("-")


def write_atomic(path, data):
    """Replace path with data (bytes) through a temp file; returns True if it changed."""
    directory = os.path.dirname(path)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    try:
        with open(path, "rb") as stream:
            if stream.read() == data:
                os.chmod(path, 0o600)
                return False
    except FileNotFoundError:
        pass
    fd, tmp = tempfile.mkstemp(prefix=".tmp-", dir=directory)
    try:
        with os.fdopen(fd, "wb") as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    return True


def secret_path(credentials_dir, name):
    if os.path.basename(name) != name or name in ("", ".", ".."):
        raise SystemExit(f"secret file name must be a plain file name, got {name!r}")
    return os.path.join(credentials_dir, name)


def read_secret(credentials_dir, name):
    if not name:
        return ""
    try:
        with open(secret_path(credentials_dir, name), encoding="utf-8") as stream:
            return stream.read().rstrip("\n")
    except FileNotFoundError:
        return ""


def render(kind, rows, credentials_dir):
    spec = KINDS[kind]
    out = io.StringIO()
    writer = csv.DictWriter(out, fieldnames=spec["columns"], lineterminator="\n")
    writer.writeheader()
    for key in sorted(rows):
        row = rows[key]
        files = row.get("secret_files", {})
        full = {column: str(row.get(column, "")) for column in spec["columns"]}
        for column in spec["secrets"]:
            full[column] = read_secret(credentials_dir, files.get(column, ""))
        missing = [c for c in required_secrets(kind, row) if not full[c]]
        if missing:
            raise SystemExit(
                f"{kind} row {key!r}: no value for {', '.join(missing)} "
                f"(expected in {credentials_dir}: {', '.join(files.get(c, '?') for c in missing)})"
            )
        writer.writerow(full)
    return out.getvalue().encode("utf-8")


def upsert(kind, meta_rows, credentials_dir):
    spec = KINDS[kind]
    row = json.load(sys.stdin)
    if not row.get(spec["key"]):
        raise SystemExit(f"stdin row needs a non-empty {spec['key']!r}")
    leaked = [c for c in spec["secrets"] if c in row]
    if leaked:
        raise SystemExit(f"secrets must be passed in the environment, not stdin: {', '.join(leaked)}")
    files = row.get("secret_files", {})
    for column in spec["secrets"]:
        value = os.environ.get("KASM_CSV_" + column.upper(), "")
        if not value:
            continue
        if not files.get(column):
            raise SystemExit(f"KASM_CSV_{column.upper()} given but no secret_files[{column!r}]")
        if read_secret(credentials_dir, files[column]) != value:
            write_atomic(secret_path(credentials_dir, files[column]), (value + "\n").encode("utf-8"))
    meta_rows[row[spec["key"]]] = {k: str(v) for k, v in row.items() if k != "secret_files"}
    meta_rows[row[spec["key"]]]["secret_files"] = dict(files)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--kind", choices=sorted(KINDS), required=True)
    parser.add_argument("--csv-dir", required=True)
    parser.add_argument("--credentials-dir", required=True)
    parser.add_argument("--project", default="", help="kasm_training_project; part of the CSV name")
    parser.add_argument("--from-credentials", action="store_true",
                        help="do not read stdin: render the CSV again from the credentials directory")
    args = parser.parse_args(argv)

    spec = KINDS[args.kind]
    name = "-".join(p for p in (spec["prefix"], slug(args.project)) if p) + ".csv"
    csv_path = os.path.join(args.csv_dir, name)
    meta_path = os.path.join(args.credentials_dir, META_NAME)
    os.makedirs(args.credentials_dir, mode=0o700, exist_ok=True)
    with open(os.path.join(args.credentials_dir, ".cluster-csv.lock"), "a", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(meta_path, encoding="utf-8") as stream:
                meta = json.load(stream)
        except FileNotFoundError:
            meta = {}
        rows = meta.setdefault(spec["section"], {})
        if args.from_credentials:
            if not rows:
                raise SystemExit(f"no {spec['section']} recorded in {meta_path}")
        else:
            upsert(args.kind, rows, args.credentials_dir)
        data = render(args.kind, rows, args.credentials_dir)
        meta_changed = write_atomic(meta_path, (json.dumps(meta, indent=2, sort_keys=True) + "\n").encode("utf-8"))
        csv_changed = write_atomic(csv_path, data)
    print("csv: changed" if (meta_changed or csv_changed) else "csv: unchanged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
