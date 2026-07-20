#!/usr/bin/env python3

import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNTIMES = {
    "bash": ["bash", str(ROOT / "scripts/rows.bash")],
    "python": ["python3", str(ROOT / "scripts/rows.py")],
}
if shutil.which("lua"):
    RUNTIMES["lua"] = ["lua", str(ROOT / "scripts/rows.lua")]


class HostProcessDetectionTest(unittest.TestCase):
    def run_rows(self, runtime, foreground):
        with tempfile.TemporaryDirectory() as tmp:
            bin_dir = Path(tmp)
            self.write_executable(
                bin_dir / "tmux",
                """#!/bin/sh
case "$1" in
  show-option) exit 0 ;;
  list-panes) printf 'fixture\\t@1\\t1\\t%%1\\t0\\tnpm\\t/tmp/project\\t/dev/pts/24\\t\\t\\t\\t\\t\\t\\t\\t\\t\\t\\t\\t\\n' ;;
esac
""",
            )
            self.write_executable(
                bin_dir / "ps",
                """#!/bin/sh
if [ "$1" = "-C" ]; then
  printf 'pts/24 200 %s opencode\\n'
else
  printf 'pts/24 100 300 zsh\\npts/24 200 %s opencode\\npts/24 300 300 npm run dev\\n'
fi
""" % (("200", "200") if foreground else ("300", "300")),
            )

            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:{env['PATH']}"
            return subprocess.check_output(RUNTIMES[runtime], env=env, text=True)

    @staticmethod
    def write_executable(path, contents):
        path.write_text(contents)
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def test_detached_agent_on_host_tty_is_ignored(self):
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                self.assertEqual("", self.run_rows(runtime, foreground=False))

    def test_foreground_agent_on_host_tty_is_detected(self):
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                output = self.run_rows(runtime, foreground=True)
                self.assertIn("fixture:1.0", output)
                self.assertIn("unknown", output)


if __name__ == "__main__":
    unittest.main()
