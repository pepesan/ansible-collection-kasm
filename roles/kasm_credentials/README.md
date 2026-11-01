# kasm_credentials

**Fully qualified name:** `pepesan.kasm.kasm_credentials` (collection [`pepesan.kasm`](https://galaxy.ansible.com/ui/repo/published/pepesan/kasm/))

Generates random, per-host Kasm admin/user passwords (persisted on the
control node so repeated runs reuse them) and records this host's
credentials in a shared access CSV named after the inventory used
(`access-data-<inventory>.csv`, e.g. `-i inventory-my-course` →
`access-data-inventory-my-course.csv`), one row per IP. Used by [`kasm`](../kasm/README.md) and
reads the same `student` password file [`student`](../student/README.md)
generates, to include it in the same CSV row.

Not covered by any Galaxy role or collection — this is Kasm-specific
bookkeeping with no equivalent upstream.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `kasm_credentials_dir` | `{{ playbook_dir }}/.credentials` | Where generated password files live (keep in sync with `student_credentials_dir`) |
| `kasm_admin_password` / `kasm_user_password` | random, persisted | Override with `-e` to set fixed passwords |
| `kasm_credentials_admin_user` / `_user_user` | `admin@kasm.local` / `user@kasm.local` | Usernames recorded in the CSV |
| `kasm_credentials_student_name` | `{{ student_name | default("student") }}` | Name of the Linux user created by [`student`](../student/README.md); follows `student_name` automatically so the right password file is read |
| `kasm_credentials_csv_prefix` | `access-data` | Prefix of the CSV file name (letters, digits, `.`, `_`, `-`). The repository `.gitignore` only covers `access-data-*` (and the old `datos-acceso-*`): add your pattern if you change it |
| `kasm_credentials_csv_name` | `access-data-<inventory file name>.csv` | Exact CSV file name, derived from the inventory file of the run (`inventory_file`). No date: every run from the same inventory lands in the same file, and the name says which hosts it holds. Set to `""` to fall back to the day-of-run naming (below). Must be a plain `*.csv` name; the script rejects paths |
| `kasm_training_project` | `""` | Only when `kasm_credentials_csv_name` is `""`: optional course prefix in `access-data[-<proyecto>]-<date of the run>.csv`; a new file each day |
| `kasm_credentials_csv_dir` | `{{ playbook_dir }}` | Where the CSV is written |

Requires `kasm_domain` to be set by the caller (normally provided by
`kasm`).

## Row order

Rows are sorted by the host name of the Kasm URL in natural order (`node2` before `node10`,
`node30` before `node31`), with the IP as tie-breaker. An existing, unsorted CSV is reordered on the next run.

## Idempotency

`files/update_credentials_csv.py` compares the row it's about to write
against what's already there for this host's IP; it only rewrites the file
(and prints `CHANGED ...`) when something actually differs, printing
`OK ... already up to date` otherwise. The Ansible task's `changed_when`
reads that marker, so a second run with the same inputs reports no change.

## Concurrency

The CSV update is safe for parallel multi-host runs: `files/update_credentials_csv.py`
uses a blocking `flock` around the read-modify-write cycle and writes
atomically (temp file + `os.replace`), so concurrent hosts delegating to the
same control node never corrupt the file or lose a row.

## Example

```yaml
- hosts: ubuntu
  roles:
    - role: pepesan.kasm.kasm_credentials
      vars:
        kasm_domain: "{{ node_name }}.example.com"
```
