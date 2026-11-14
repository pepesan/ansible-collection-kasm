#!/usr/bin/env python3
"""Writes user-access-<project>.csv: update_cluster_csv.py with --kind user."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from update_cluster_csv import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main(["--kind", "user", *sys.argv[1:]]))
