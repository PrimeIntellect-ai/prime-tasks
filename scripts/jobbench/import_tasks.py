# /// script
# requires-python = ">=3.12"
# dependencies = ["huggingface-hub>=0.34", "tomli-w>=1.2"]
# ///
"""Export pinned upstream Harbor packages for the shared JobBench runtime."""

import argparse
import json
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

import tomli_w

UPSTREAM_REVISION = "660b33a86ed032559df0b2fdc1ad38cf7ceb83f3"
DATASET_REVISION = "d43a66575635da0d3f6cb9a20976dc1a60f3ffc9"
IMAGE = "prime/primeintellect/jobbench:660b33a"

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("upstream", type=Path, help="Checkout of Job-Bench/job-bench-eval at the pinned revision")
args = parser.parse_args()
upstream = args.upstream.resolve()
revision = subprocess.check_output(["git", "-C", str(upstream), "rev-parse", "HEAD"], text=True).strip()
if revision != UPSTREAM_REVISION:
    raise ValueError(f"Expected upstream {UPSTREAM_REVISION}, got {revision}")

sys.path.insert(0, str(upstream / "harbor"))
from jobbench_harbor.hf_source import fetch_snapshot  # noqa: E402
from jobbench_harbor.prepare import generate  # noqa: E402

source = fetch_snapshot(upstream / "harbor/.cache/huggingface", repo_id="JobBench/job-bench", revision=DATASET_REVISION)
manifest = generate(
    source.path,
    upstream / "harbor",
    repo_id="JobBench/job-bench",
    revision=DATASET_REVISION,
    judge_path=upstream / "eval/judge.py",
    remote_files=source.remote_files,
)
destination = Path(__file__).resolve().parents[2] / "datasets/jobbench"
for record in manifest["tasks"]:
    task_dir = destination / record["split"] / record["id"]
    shutil.copytree(upstream / "harbor/tasks" / record["id"], task_dir, dirs_exist_ok=True)
    config = tomllib.loads((task_dir / "task.toml").read_text())
    config["environment"]["docker_image"] = IMAGE
    # A fresh copy of the dependency-only solver image receives tests after the solve.
    del config["verifier"]["environment"]
    config["verifier"]["env"].update(
        JUDGE_API_BASE="${JUDGE_API_BASE:-https://api.pinference.ai/api/v1}",
        JUDGE_API_KEY="${PRIME_API_KEY}",
        JUDGE_MODEL="${JUDGE_MODEL:-openai/gpt-5.6-luna}",
    )
    (task_dir / "task.toml").write_text(tomli_w.dumps(config))
    (task_dir / "tests/Dockerfile").unlink()
    (task_dir / "tests/test.sh").write_text(
        "#!/bin/sh\nset -eu\n\nexec /opt/jobbench-verifier/bin/python /tests/verify.py\n"
    )
    (task_dir / "environment/Dockerfile").unlink()
    (task_dir / "environment/requirements.txt").unlink()

provenance = {
    "upstream_repo": "https://github.com/Job-Bench/job-bench-eval",
    "upstream_revision": UPSTREAM_REVISION,
    "dataset_repo": "JobBench/job-bench",
    "dataset_revision": DATASET_REVISION,
    "image": IMAGE,
    "tasks": manifest["tasks"],
}
(destination / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
shutil.copyfile(upstream / "LICENSE", destination / "LICENSE")
print(f"Exported {len(manifest['tasks'])} tasks to {destination}")
