# /// script
# requires-python = ">=3.12"
# dependencies = ["harbor==0.25.0"]
# ///
"""Export the pinned SWE-rebench V2.1 RL Harbor Hub package into datasets/swe-rebench-v2.1
and convert every task to a separate verifier.

The verifier box receives only `/logs/artifacts/model.patch`, the agent's diff against the
image's starting tree, and its `tests/test.sh` applies that diff before the held-out test patch.
"""

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PACKAGE = "ibragim-badertdinov/swe-rebench-v2.1-rl"
DIGEST = "sha256:0dcba0d99e8c2bc7f1a8aefdd2e3cf8f5aae2387659d6390a06446ed5f3612b3"
NUM_TASKS = 13_337
DATASET_DIR = Path(__file__).resolve().parents[2] / "datasets" / "swe-rebench-v2.1"

MODEL_PATCH = "/logs/artifacts/model.patch"

# Prime resolves `repo:tag@sha256:digest` by its tag; the digest alone selects the pinned image.
TAGGED_DIGEST = re.compile(r'^(docker_image = "[^":@]+(?:/[^":@]+)*):[^"@]+(@sha256:[0-9a-f]{64}")$', re.M)

APPLY_MODEL_PATCH = f"""\
if [ -s {MODEL_PATCH} ]; then
  if ! (EXCLUDES=(); apply_patch {MODEL_PATCH}) > "$V/model_patch_apply.log" 2>&1; then
    echo "MODEL_PATCH_APPLY_FAILED"
    cat "$V/model_patch_apply.log"
    exit 0
  fi
fi
"""


def replace_once(text: str, old: str, new: str, path: Path) -> str:
    if text.count(old) != 1:
        raise SystemExit(f"{path}: expected one {old!r}")
    return text.replace(old, new)


def convert(task_dir: Path) -> None:
    toml_path = task_dir / "task.toml"
    text = replace_once(
        toml_path.read_text(), "[verifier]\n", '[verifier]\nenvironment_mode = "separate"\n', toml_path
    )
    text = TAGGED_DIGEST.sub(r"\1\2", text)
    if not re.search(r'^docker_image = "[^"]+@sha256:[0-9a-f]{64}"$', text, re.M) or re.search(
        r'^docker_image = "[^"@]+:[^"@/]+@', text, re.M
    ):
        raise SystemExit(f"{toml_path}: docker_image is not a digest-only reference")
    toml_path.write_text(text)

    script_path = task_dir / "tests" / "test.sh"
    script = script_path.read_text()
    script = replace_once(
        script, "set -uo pipefail\n", 'set -uo pipefail\nulimit -n "$(ulimit -Hn)" 2>/dev/null || true\n', script_path
    )
    script = replace_once(
        script, 'for f in "${TEST_FILES[@]}"; do\n', APPLY_MODEL_PATCH + 'for f in "${TEST_FILES[@]}"; do\n', script_path
    )
    script_path.write_text(script)


def main() -> None:
    harbor = Path(sys.executable).parent / "harbor"
    with tempfile.TemporaryDirectory() as tmp:
        command = [str(harbor), "datasets", "download", f"{PACKAGE}@{DIGEST}", "--export", "-o", tmp]
        subprocess.run(command, check=True)
        tasks = sorted(path.parent for path in Path(tmp).glob("*/*/task.toml"))
        if len(tasks) != NUM_TASKS:
            raise SystemExit(f"expected {NUM_TASKS} tasks, exported {len(tasks)}")
        for stale in DATASET_DIR.glob("*/task.toml"):
            shutil.rmtree(stale.parent)
        for task in tasks:
            shutil.copytree(task, DATASET_DIR / task.name)
            convert(DATASET_DIR / task.name)
    print(f"exported and converted {len(tasks)} tasks in {DATASET_DIR}")


if __name__ == "__main__":
    main()
