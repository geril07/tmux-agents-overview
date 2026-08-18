#!/usr/bin/env python3

import json
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


class AntigravityIntegrationTest(unittest.TestCase):
    @staticmethod
    def write_executable(path, contents):
        path.write_text(contents)
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def test_antigravity_adapter_emits_valid_json(self):
        script = ROOT / "scripts/adapters/antigravity.sh"
        self.assertTrue(os.access(script, os.X_OK))
        out = subprocess.check_output([str(script), "/tmp/test-state.sh"], text=True)
        data = json.loads(out)
        self.assertIn("tmux-agents-overview", data)
        hooks = data["tmux-agents-overview"]
        self.assertIn("PreInvocation", hooks)
        self.assertIn("PreToolUse", hooks)
        self.assertIn("PostToolUse", hooks)
        self.assertIn("Stop", hooks)

        # Check PreInvocation command
        self.assertEqual(
            hooks["PreInvocation"][0]["command"],
            "/tmp/test-state.sh antigravity working busy",
        )
        # Check PreToolUse matcher & command
        self.assertEqual(hooks["PreToolUse"][0]["matcher"], "ask_question")
        self.assertEqual(
            hooks["PreToolUse"][0]["hooks"][0]["command"],
            "/tmp/test-state.sh antigravity waiting question",
        )
        # Check PostToolUse matcher & command
        self.assertEqual(hooks["PostToolUse"][0]["matcher"], "*")
        self.assertEqual(
            hooks["PostToolUse"][0]["hooks"][0]["command"],
            "/tmp/test-state.sh antigravity working busy",
        )
        # Check Stop command
        self.assertEqual(
            hooks["Stop"][0]["command"],
            "/tmp/test-state.sh antigravity idle done",
        )

    def test_direct_agy_command_detection(self):
        for cmd_name in ["agy", "antigravity"]:
            with tempfile.TemporaryDirectory() as tmp:
                bin_dir = Path(tmp)
                self.write_executable(
                    bin_dir / "tmux",
                    f"""#!/bin/sh
case "$1" in
  show-option)
    if [ "$3" = "@agents_overview_columns" ]; then
      printf 'pane,status,age,agent,command'
    fi
    exit 0
    ;;
  list-panes)
    printf 'mysess\\t@1\\t1\\t%%1\\t0\\t{cmd_name}\\t/tmp/myproject\\t/dev/pts/1\\t\\t\\t\\t\\t\\t\\t\\t\\t\\t\\t\\t\\n'
    ;;
esac
""",
                )
                self.write_executable(
                    bin_dir / "ps",
                    "#!/bin/sh\nexit 0\n",
                )

                env = os.environ.copy()
                env["PATH"] = f"{bin_dir}:{env['PATH']}"
                for runtime in RUNTIMES:
                    with self.subTest(runtime=runtime, cmd_name=cmd_name):
                        output = subprocess.check_output(RUNTIMES[runtime], env=env, text=True)
                        self.assertIn("mysess:1.0", output)
                        self.assertIn("unknown", output)
                        self.assertIn("antigravity", output)
                        self.assertIn(cmd_name, output)

    def test_helpers_registry_contains_antigravity(self):
        helpers_script = ROOT / "scripts/helpers.sh"
        cmd = f'. "{helpers_script}" && is_known_agent antigravity && agent_process_names antigravity'
        out = subprocess.check_output(["bash", "-c", cmd], text=True).strip()
        self.assertEqual("agy antigravity", out)


if __name__ == "__main__":
    unittest.main()
