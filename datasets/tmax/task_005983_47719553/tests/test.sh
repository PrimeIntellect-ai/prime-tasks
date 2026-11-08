#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import shlex
import subprocess
from pathlib import Path

SCRIPT = Path("/home/user/prepare_pipeline.sh")
METADATA = Path("/home/user/user_metadata.csv")
ACTIVITY = Path("/home/user/user_activity.csv")
JOINED = Path("/home/user/joined.csv")
CI_RESULTS = Path("/home/user/ci_results.txt")


def run_pipeline():
    JOINED.unlink(missing_ok=True)
    CI_RESULTS.unlink(missing_ok=True)
    result = subprocess.run(["bash", str(SCRIPT)], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Script execution failed with return code {result.returncode}.\n"
        f"Stderr: {result.stderr}"
    )
    assert JOINED.is_file(), f"File {JOINED} was not created by the script."
    assert CI_RESULTS.is_file(), f"File {CI_RESULTS} was not created by the script."
    return JOINED.read_text().strip(), CI_RESULTS.read_text().strip()


def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/prepare_pipeline.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_pipeline_script_environment_variables():
    script_path = "/home/user/prepare_pipeline.sh"
    with open(script_path, "r") as f:
        content = f.read()
    assert "OPENBLAS_NUM_THREADS=1" in content, "OPENBLAS_NUM_THREADS=1 not found in script."
    assert "PYTHONHASHSEED=0" in content, "PYTHONHASHSEED=0 not found in script."

    # The required assignments must be actual export commands in the initial
    # command block, rather than comments or strings elsewhere in the file.
    seen = set()
    for raw_line in content.splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        parts = shlex.split(stripped, comments=True)
        if not parts:
            continue
        if parts[0] != "export":
            break
        for token in parts[1:]:
            if token == "OPENBLAS_NUM_THREADS=1":
                seen.add("OPENBLAS_NUM_THREADS")
            elif token == "PYTHONHASHSEED=0":
                seen.add("PYTHONHASHSEED")
        if seen == {"OPENBLAS_NUM_THREADS", "PYTHONHASHSEED"}:
            break

    assert "OPENBLAS_NUM_THREADS" in seen, (
        "OPENBLAS_NUM_THREADS=1 must be exported at the beginning of the script."
    )
    assert "PYTHONHASHSEED" in seen, (
        "PYTHONHASHSEED=0 must be exported at the beginning of the script."
    )


def test_pipeline_execution_and_outputs():
    joined_content, ci_content = run_pipeline()

    expected_joined = (
        "1,25,US,100,5\n"
        "2,30,UK,150,10\n"
        "3,22,US,200,2\n"
        "4,35,CA,50,0\n"
        "5,28,UK,120,8"
    )
    assert joined_content.splitlines() == expected_joined.splitlines(), (
        f"Content of {JOINED} is incorrect."
    )

    expected_ci = "74.96,173.04"
    assert ci_content == expected_ci, (
        f"Content of {CI_RESULTS} is incorrect. Expected '{expected_ci}', got '{ci_content}'."
    )


def test_pipeline_on_unseen_inputs():
    rng = secrets.SystemRandom()
    original_metadata = METADATA.read_bytes()
    original_activity = ACTIVITY.read_bytes()

    try:
        for _ in range(2):
            n = rng.randint(4, 8)
            ids = rng.sample(range(1, 10), n)
            metadata_rows = {}
            activity_rows = {}

            for user_id in ids:
                metadata_rows[user_id] = (
                    rng.randint(18, 75),
                    rng.choice(["US", "UK", "CA", "DE", "FR", "JP"]),
                )
                activity_rows[user_id] = (
                    rng.randint(50, 250),
                    rng.randint(0, 30),
                )

            metadata_order = ids[:]
            activity_order = ids[:]
            rng.shuffle(metadata_order)
            rng.shuffle(activity_order)

            METADATA.write_text("".join(
                f"{user_id},{metadata_rows[user_id][0]},{metadata_rows[user_id][1]}\n"
                for user_id in metadata_order
            ))
            ACTIVITY.write_text("".join(
                f"{user_id},{activity_rows[user_id][0]},{activity_rows[user_id][1]}\n"
                for user_id in activity_order
            ))

            joined_content, ci_content = run_pipeline()

            sorted_ids = sorted(ids)
            expected_lines = [
                f"{user_id},{metadata_rows[user_id][0]},{metadata_rows[user_id][1]},"
                f"{activity_rows[user_id][0]},{activity_rows[user_id][1]}"
                for user_id in sorted_ids
            ]
            assert joined_content.splitlines() == expected_lines, (
                "Joined output is incorrect for unseen shuffled input data."
            )

            clicks = [activity_rows[user_id][0] for user_id in sorted_ids]
            mean = sum(clicks) / len(clicks)
            sample_variance = sum((value - mean) ** 2 for value in clicks) / (len(clicks) - 1)
            margin = 1.96 * math.sqrt(sample_variance) / math.sqrt(len(clicks))
            expected_ci = f"{mean - margin:.2f},{mean + margin:.2f}"
            assert ci_content == expected_ci, (
                f"CI is incorrect for unseen data. Expected '{expected_ci}', got '{ci_content}'."
            )
    finally:
        METADATA.write_bytes(original_metadata)
        ACTIVITY.write_bytes(original_activity)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
