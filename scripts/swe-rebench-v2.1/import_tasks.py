# /// script
# requires-python = ">=3.12"
# dependencies = ["harbor==0.25.0"]
# ///
"""Export the pinned SWE-rebench V2.1 RL Harbor Hub package into datasets/swe-rebench-v2.1."""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PACKAGE = "ibragim-badertdinov/swe-rebench-v2.1-rl"
DIGEST = "sha256:0dcba0d99e8c2bc7f1a8aefdd2e3cf8f5aae2387659d6390a06446ed5f3612b3"
NUM_TASKS = 13_337
DATASET_DIR = Path(__file__).resolve().parents[2] / "datasets" / "swe-rebench-v2.1"


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
    print(f"exported {len(tasks)} tasks to {DATASET_DIR}")


if __name__ == "__main__":
    main()
