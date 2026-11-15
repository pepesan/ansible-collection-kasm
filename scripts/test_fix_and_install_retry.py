"""Regression tests for the Kasm installer wrapper (no network or Ansible).

Run from outside the repository:
    python3 /path/to/collection/scripts/test_fix_and_install_retry.py
"""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


DEFAULT_SCRIPT = Path(__file__).resolve().parents[1] / "roles/kasm/files/fix_and_install_kasm.sh"
INSTALL_SCRIPT = Path(os.environ.get("KASM_INSTALL_SCRIPT", DEFAULT_SCRIPT))


class InstallRetryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.release = self.root / "release"
        self.release.mkdir()
        self.attempts = self.root / "attempts"
        self.marker = self.root / "installed"
        self.log = self.root / "install.log"
        self.docker = self.root / "fake-docker"
        self.docker.write_text(
            "#!/usr/bin/env bash\n"
            "set -eu\n"
            "if [ \"${1:-}\" = ps ] && [ \"${INSTALL_TEST_MODE:-}\" = plugin_race ] && "
            "[ -f \"$INSTALL_ATTEMPT_FILE\" ]; then\n"
            "  count=$(wc -l < \"$INSTALL_ATTEMPT_FILE\")\n"
            "  if [ \"$count\" -ge 2 ]; then printf 'kasm_db\\n'; fi\n"
            "fi\n"
        )
        self.docker.chmod(0o755)
        self.install = self.release / "install.sh"
        self.install.write_text(
            "#!/usr/bin/env bash\n"
            "set -eu\n"
            "count=0\n"
            "[ ! -f \"$INSTALL_ATTEMPT_FILE\" ] || count=$(wc -l < \"$INSTALL_ATTEMPT_FILE\")\n"
            "count=$((count + 1))\n"
            "printf '%s\\n' \"$count\" >> \"$INSTALL_ATTEMPT_FILE\"\n"
            "if [ \"$INSTALL_TEST_MODE\" = port_conflict ]; then\n"
            "  echo 'Port (443) is in use. Installation cannot continue.'\n"
            "  exit 255\n"
            "fi\n"
            "if [ \"$count\" -eq 1 ]; then\n"
            "  echo 'dial unix /run/kasmlogger/kasmlogger.sock: connect: connection refused'\n"
            "  exit 1\n"
            "fi\n"
            "echo 'install complete'\n"
            "exit 0\n"
        )

        fake_bin = self.root / "bin"
        fake_bin.mkdir()
        sleep = fake_bin / "sleep"
        sleep.write_text("#!/usr/bin/env bash\nexit 0\n")
        sleep.chmod(0o755)

    def tearDown(self):
        self.temp.cleanup()

    def run_wrapper(self, mode):
        env = os.environ.copy()
        env.update(
            {
                "KASM_ADMIN_PASSWORD": "test-only-admin",
                "KASM_USER_PASSWORD": "test-only-user",
                "KASM_RELEASE_DIR": str(self.release),
                "KASM_INSTALL_MARKER": str(self.marker),
                "KASM_REQUIRED_SERVICES": "kasm_db",
                "KASM_INSTALL_ARGS": "--install-profile noninteractive",
                "KASM_PASSWORDS_IN_ARGS": "false",
                "KASM_DOCKER": str(self.docker),
                "KASM_LOG_FILE": str(self.log),
                "INSTALL_ATTEMPT_FILE": str(self.attempts),
                "INSTALL_TEST_MODE": mode,
                "TMPDIR": str(self.root),
                "PATH": f"{self.root / 'bin'}:{env['PATH']}",
            }
        )
        return subprocess.run(
            ["bash", str(INSTALL_SCRIPT)],
            cwd=self.root,
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )

    def test_port_conflict_fails_once_without_marking_install(self):
        result = self.run_wrapper("port_conflict")

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.attempts.read_text().splitlines(), ["1"])
        self.assertIn("Port (443) is in use. Installation cannot continue.", result.stdout)
        self.assertIn("not retrying this deterministic error", result.stdout)
        self.assertFalse(self.marker.exists())
        self.assertEqual(list(self.root.glob("kasm-install-output.*")), [])

    def test_transient_plugin_race_still_retries_and_marks_success(self):
        result = self.run_wrapper("plugin_race")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.attempts.read_text().splitlines(), ["1", "2"])
        self.assertIn("attempt 2/3", result.stdout)
        self.assertTrue(self.marker.exists())
        self.assertEqual(list(self.root.glob("kasm-install-output.*")), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
