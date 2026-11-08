# /// script
# requires-python = ">=3.12"
# dependencies = ["harbor==0.25.0", "huggingface-hub>=0.26", "pyarrow>=17"]
# ///
"""Export the pinned SWE-rebench V2.1 RL Harbor Hub package into datasets/swe-rebench-v2.1
and convert every task to a separate verifier.

A collect hook writes the agent's repository diff against the task's base commit to
`/logs/artifacts/model.patch`, the only state the verifier box receives; its `tests/test.sh`
applies that diff before the held-out test patch.
"""

import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

import pyarrow.parquet as pq
from huggingface_hub import hf_hub_download

PACKAGE = "ibragim-badertdinov/swe-rebench-v2.1-rl"
DIGEST = "sha256:0dcba0d99e8c2bc7f1a8aefdd2e3cf8f5aae2387659d6390a06446ed5f3612b3"
NUM_TASKS = 13_337
DATASET_DIR = Path(__file__).resolve().parents[2] / "datasets" / "swe-rebench-v2.1"

# V2.1 metadata omits the base commit; the V2 rows the tasks come from carry it.
V2_REPO = "nebius/SWE-rebench-V2"
V2_REVISION = "d7608f017a29ab256400ad4b73d5248d97204966"
V2_FILE = "data/train-00000-of-00001.parquet"

MODEL_PATCH = "/logs/artifacts/model.patch"

APPLY_MODEL_PATCH = f"""\
if [ -s {MODEL_PATCH} ]; then
  if ! (EXCLUDES=(); apply_patch {MODEL_PATCH}) > "$V/model_patch_apply.log" 2>&1; then
    echo "MODEL_PATCH_APPLY_FAILED"
    cat "$V/model_patch_apply.log"
    exit 0
  fi
fi
"""


def base_commits() -> dict[str, str]:
    path = hf_hub_download(V2_REPO, V2_FILE, repo_type="dataset", revision=V2_REVISION)
    table = pq.read_table(path, columns=["instance_id", "base_commit"])
    return dict(zip(table.column("instance_id").to_pylist(), table.column("base_commit").to_pylist()))


def replace_once(text: str, old: str, new: str, path: Path) -> str:
    if text.count(old) != 1:
        raise SystemExit(f"{path}: expected one {old!r}")
    return text.replace(old, new)


def convert(task_dir: Path, base_commit: str) -> None:
    toml_path = task_dir / "task.toml"
    text = toml_path.read_text()
    workdir = tomllib.loads(text)["environment"]["workdir"]
    # A repository the agent broke yields an empty patch, which grades as no change.
    collect = (
        f"mkdir -p /logs/artifacts && {{ cd {workdir} && git add -A && "
        f"git diff --cached --binary {base_commit} > {MODEL_PATCH} || : > {MODEL_PATCH}; }}"
    )
    text = replace_once(text, "[verifier]\n", '[verifier]\nenvironment_mode = "separate"\n', toml_path)
    text += f'\n[[verifier.collect]]\ncommand = "{collect}"\ntimeout_sec = 900\n'
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
    commits = base_commits()
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
            convert(DATASET_DIR / task.name, commits[task.name])
    print(f"exported and converted {len(tasks)} tasks in {DATASET_DIR}")


if __name__ == "__main__":
    main()
