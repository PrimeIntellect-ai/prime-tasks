#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile

TASK_DIR = "/home/user/task"
LEVELS = [2, 4, 8, 16]


def test_aggregate_sh_fixed():
    script_path = os.path.join(TASK_DIR, "aggregate.sh")
    assert os.path.isfile(script_path), "aggregate.sh is missing."
    assert os.access(script_path, os.X_OK), "aggregate.sh is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    # Retain the original source-level assertion.
    original_cmd = 'find . -maxdepth 1 -name "partial_${N}_*.dat" | xargs awk'
    assert original_cmd not in content, (
        "aggregate.sh still uses the non-deterministic `find ... | xargs awk` without sorting."
    )


def test_results_and_log():
    script_path = os.path.join(TASK_DIR, "aggregate.sh")
    reference_path = os.path.join(TASK_DIR, "reference.dat")
    distance_script = os.path.join(TASK_DIR, "compute_distance.py")

    # Derive all expected ordered aggregations before executing the submitted script.
    expected_results = {}
    expected_distances = {}
    for N in LEVELS:
        files = [f"partial_{N}_{i}.dat" for i in range(1, N + 1)]
        files_paths = [os.path.join(TASK_DIR, name) for name in files]
        for fp in files_paths:
            assert os.path.isfile(fp), f"Expected partial file {fp} is missing."

        awk_cmd = [
            "awk",
            "{a[FNR]+=$1} END {for(i=1;i<=1000;i++) print a[i]}",
        ] + files_paths
        ordered = subprocess.run(
            awk_cmd, capture_output=True, text=True, check=True, timeout=30
        ).stdout
        expected_results[N] = ordered

        with tempfile.NamedTemporaryFile(mode="w", suffix=".dat", delete=False) as tmp:
            tmp.write(ordered)
            temp_result = tmp.name
        try:
            dist_cmd = [
                "python3",
                distance_script,
                temp_result,
                reference_path,
            ]
            expected_distances[N] = subprocess.run(
                dist_cmd, capture_output=True, text=True, check=True, timeout=30
            ).stdout.strip()
        finally:
            os.remove(temp_result)

    # Remove pre-existing outputs and actually execute aggregate.sh for every required N.
    for N in LEVELS:
        result_file = os.path.join(TASK_DIR, f"result_{N}.dat")
        if os.path.lexists(result_file):
            os.remove(result_file)

        subprocess.run(
            [script_path, str(N)],
            cwd=TASK_DIR,
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )

        assert os.path.isfile(result_file), f"result_{N}.dat does not exist."
        with open(result_file, "r") as f:
            actual_result = f.read()
        assert actual_result == expected_results[N], (
            f"result_{N}.dat is not the exact aggregation produced by processing "
            f"partial_{N}_1.dat through partial_{N}_{N}.dat in increasing numerical order."
        )

    log_file = os.path.join(TASK_DIR, "convergence.log")
    assert os.path.isfile(log_file), "convergence.log does not exist."

    with open(log_file, "r") as f:
        log_lines = [line.strip() for line in f if line.strip()]

    assert len(log_lines) == 4, (
        f"convergence.log should have exactly 4 lines, but found {len(log_lines)}."
    )

    for idx, N in enumerate(LEVELS):
        expected_line = f"N={N} distance={expected_distances[N]}"
        assert log_lines[idx] == expected_line, (
            f"Log line {idx + 1} is incorrect.\n"
            f"Expected: '{expected_line}'\n"
            f"Got:      '{log_lines[idx]}'"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
