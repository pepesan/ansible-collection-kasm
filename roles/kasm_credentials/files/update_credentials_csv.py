#!/usr/bin/env python3
"""Creates/updates a row (keyed by IP) in the Kasm deployment credentials CSV.
Rows are kept sorted by the host name of their Kasm URL (natural order).

Runs on the Ansible control node (delegate_to: localhost), never on the
remote host. Passwords are passed via environment variables, not command
line arguments, so they never show up in the process list (ps aux) or shell
history.

Safe for concurrent runs: with forks>1 (or several separate runs close in
time) multiple inventory hosts can invoke this script almost simultaneously,
all delegating to the same control node. A blocking flock covers both the
decision of which CSV file to use/create and the full read-modify-write
cycle, and the final write is atomic (temp file + os.replace) so the CSV is
never left half-written if the process is interrupted.
"""
import csv
import fcntl
import os
import re
import sys
import argparse
from urllib.parse import urlparse
from datetime import date

COLUMNS = [
    "ip",
    "student_password",
    "kasm_url",
    "kasm_admin_user",
    "kasm_admin_password",
    "kasm_user_user",
    "kasm_user_password",
]


def sanitize_prefix(training_project):
    """Turns the course/cohort name into a filesystem-safe slug (no spaces
    or special characters)."""
    if not training_project:
        return ""
    slug = "".join(c if c.isalnum() else "-" for c in training_project.strip())
    while "--" in slug:
        slug = slug.replace("--", "-")
    return slug.strip("-").lower()


def resolve_csv_path(directory, training_project="", csv_prefix="access-data"):
    """Legacy naming, used only when no explicit --csv-name is given: always
    the file dated with the day of the run, <csv_prefix>[-<course>]-<date>.csv (default prefix: access-data).
    A new day starts a new file, so the date in the name is always the day the
    rows were written (it used to reuse the oldest existing file, whose date
    then misled). The course/cohort prefix keeps credentials from different
    courses deployed in parallel from mixing in the same CSV. Must always be
    called with the lock already held."""
    prefix = sanitize_prefix(training_project)
    today = date.today().isoformat()
    name = f"{csv_prefix}-{prefix}-{today}.csv" if prefix else f"{csv_prefix}-{today}.csv"
    return os.path.join(directory, name)


def safe_csv_prefix(prefix):
    """Validates the CSV file name prefix: letters, digits, '.', '_' and '-'
    only, not empty and not starting with '.', so it can never contain a
    directory. Raises SystemExit otherwise."""
    allowed = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    if not prefix or prefix.startswith(".") or any(c not in allowed for c in prefix):
        raise SystemExit(
            f"--csv-prefix {prefix!r} is not valid "
            "(letters, digits, '.', '_' and '-' only, not empty)"
        )
    return prefix


def safe_csv_name(name):
    """Validates an explicit CSV file name: a bare file name (no directories)
    made of letters, digits, '.', '_' and '-', ending in .csv. Raises
    SystemExit otherwise, so a bad value can never write outside --csv-dir."""
    allowed = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    if (
        not name
        or name != os.path.basename(name)
        or name.startswith(".")
        or not name.endswith(".csv")
        or any(c not in allowed for c in name)
    ):
        raise SystemExit(
            f"--csv-name {name!r} is not a plain *.csv file name "
            "(letters, digits, '.', '_' and '-' only, no directories)"
        )
    return name


def natural_key(text):
    """Natural sort key: digit runs compare as numbers, so node2 < node10."""
    return [int(part) if part.isdigit() else part.lower()
            for part in re.split(r"(\d+)", text or "")]


def row_sort_key(row):
    """Sorts rows by the host name of their Kasm URL (node30 before node31),
    using the IP as a tie-breaker. Rows without a URL go last."""
    url = row.get("kasm_url", "") or ""
    host = urlparse(url).hostname or url
    return (host == "", natural_key(host), natural_key(row.get("ip", "")))


def update_row(csv_path, ip, row):
    """Returns True if the file was actually rewritten (the row is new or
    differs from what was already there), False if the existing row already
    matched and nothing was written — this lets the caller report accurate
    changed/unchanged status instead of always claiming a change."""
    rows_by_ip = {}
    if os.path.exists(csv_path):
        with open(csv_path, newline="") as f:
            reader = csv.DictReader(f)
            for existing_row in reader:
                rows_by_ip[existing_row["ip"]] = existing_row

    existing_row = rows_by_ip.get(ip)
    rows_by_ip[ip] = row
    ordered_ips = sorted(rows_by_ip, key=lambda k: row_sort_key(rows_by_ip[k]))
    # Nothing to write only if the row is unchanged AND the file is already sorted.
    if existing_row == row and list(rows_by_ip) == ordered_ips:
        return False

    tmp_path = csv_path + ".tmp"
    with open(tmp_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=COLUMNS)
        writer.writeheader()
        for ip_key in ordered_ips:
            writer.writerow(rows_by_ip[ip_key])
    os.chmod(tmp_path, 0o600)
    os.replace(tmp_path, csv_path)  # atomic within the same filesystem
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv-dir", required=True)
    parser.add_argument("--ip", required=True)
    parser.add_argument("--kasm-url", required=True)
    parser.add_argument("--kasm-admin-user", required=True)
    parser.add_argument("--kasm-user-user", required=True)
    parser.add_argument(
        "--training-project",
        default="",
        help="Optional prefix (course/cohort) so credentials from different "
             "courses deployed in parallel don't mix in the same CSV. "
             "Without this argument the classic filename is used "
             "(access-data-<date>.csv, dated with the day of the run).",
    )
    parser.add_argument(
        "--csv-prefix",
        default="access-data",
        help="Prefix of the CSV file name (default: access-data).",
    )
    parser.add_argument(
        "--csv-name",
        default="",
        help="Exact CSV file name inside --csv-dir (e.g. "
             "access-data-inventory-my-course.csv). When given it takes "
             "precedence over --training-project and over the "
             "dated naming: that one file is used as is.",
    )
    args = parser.parse_args()

    row = {
        "ip": args.ip,
        "student_password": os.environ.get("STUDENT_PASSWORD", ""),
        "kasm_url": args.kasm_url,
        "kasm_admin_user": args.kasm_admin_user,
        "kasm_admin_password": os.environ.get("KASM_ADMIN_PASSWORD", ""),
        "kasm_user_user": args.kasm_user_user,
        "kasm_user_password": os.environ.get("KASM_USER_PASSWORD", ""),
    }

    prefix = sanitize_prefix(args.training_project)

    os.makedirs(args.csv_dir, exist_ok=True)
    explicit_name = safe_csv_name(args.csv_name) if args.csv_name else ""
    if explicit_name:
        lock_name = f".{explicit_name}.lock"
    else:
        lock_name = f".{safe_csv_prefix(args.csv_prefix)}-{prefix}.lock" if prefix else f".{safe_csv_prefix(args.csv_prefix)}.lock"
    lock_path = os.path.join(args.csv_dir, lock_name)
    with open(lock_path, "w") as lock_file:
        fcntl.flock(lock_file, fcntl.LOCK_EX)  # blocking: waits its turn
        try:
            if explicit_name:
                csv_path = os.path.join(args.csv_dir, explicit_name)
            else:
                csv_path = resolve_csv_path(args.csv_dir, args.training_project, safe_csv_prefix(args.csv_prefix))
            changed = update_row(csv_path, args.ip, row)
        finally:
            fcntl.flock(lock_file, fcntl.LOCK_UN)

    if changed:
        print(f"CHANGED row for {args.ip} updated in {csv_path}")
    else:
        print(f"OK row for {args.ip} already up to date in {csv_path}")


if __name__ == "__main__":
    sys.exit(main())
