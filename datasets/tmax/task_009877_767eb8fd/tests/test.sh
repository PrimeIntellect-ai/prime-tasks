#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import secrets
import subprocess

import pytest

DATA_DIR = "/home/user/data"
REPORT_PATH = "/home/user/analysis_report.txt"
SCRIPT_PATH = "/home/user/analyze_spectroscopy.sh"


def compute_energy(filepath):
    total = 0.0
    with open(filepath, "r") as f:
        reader = csv.reader(f)
        for r, row in enumerate(reader, start=1):
            if 10 <= r <= 40:
                for c, val in enumerate(row, start=1):
                    if 20 <= c <= 80:
                        total += float(val)
    return total


def calculate_expected():
    baseline_energy = compute_energy(os.path.join(DATA_DIR, "baseline.csv"))
    max_diff = 0.0
    for i in range(1, 11):
        run_energy = compute_energy(os.path.join(DATA_DIR, f"run_{i}.csv"))
        max_diff = max(max_diff, abs(baseline_energy - run_energy))

    return {
        "baseline": f"{baseline_energy:.4f}",
        "max_diff": f"{max_diff:.4f}",
        "conclusion": "REJECT_NULL" if max_diff > 0.05 else "ACCEPT_NULL",
    }


@pytest.fixture(scope="module")
def expected_results():
    return calculate_expected()


def assert_report(expected):
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    with open(REPORT_PATH, "r") as f:
        lines = [line.strip() for line in f.read().strip().split("\n")]

    assert len(lines) == 3, f"Expected exactly 3 lines in {REPORT_PATH}, got {len(lines)}."
    assert lines[0] == f"Baseline Energy: {expected['baseline']}"
    assert lines[1] == f"Max Difference: {expected['max_diff']}"
    assert lines[2] == f"Conclusion: {expected['conclusion']}"


def run_script():
    if os.path.lexists(REPORT_PATH):
        os.unlink(REPORT_PATH)
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}. stderr: {result.stderr}"
    )


def write_challenge(accept_null):
    rng = secrets.SystemRandom()
    roi_values = {
        (r, c): rng.randint(-500, 500)
        for r in range(10, 41)
        for c in range(20, 81)
    }
    changed_cell = rng.choice(list(roi_values))

    if accept_null:
        deltas = [rng.randint(-39, 39) for _ in range(9)] + [rng.choice((-40, 40))]
    else:
        deltas = [rng.randint(-40, 40) for _ in range(9)] + [rng.choice((-80, 80))]
    rng.shuffle(deltas)

    outside_sentinels = {
        (9, 20): 731000,
        (41, 20): -829000,
        (10, 19): 937000,
        (10, 81): -643000,
    }

    def write_file(path, delta=0):
        with open(path, "w") as f:
            for r in range(1, 51):
                row = []
                for c in range(1, 101):
                    units = roi_values.get((r, c), outside_sentinels.get((r, c), 0))
                    if (r, c) == changed_cell:
                        units += delta
                    row.append(f"{units / 1000.0:.8f}")
                f.write(",".join(row) + "\n")

    write_file(os.path.join(DATA_DIR, "baseline.csv"))
    for i, delta in enumerate(deltas, start=1):
        write_file(os.path.join(DATA_DIR, f"run_{i}.csv"), delta)


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_is_bash():
    with open(SCRIPT_PATH, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="strict").strip()
    assert first_line in ("#!/bin/bash", "#!/usr/bin/bash", "#!/usr/bin/env bash"), (
        "Analysis artifact must be an executable Bash script."
    )


def test_script_executes_and_analyzes_runtime_data():
    paths = [os.path.join(DATA_DIR, "baseline.csv")] + [
        os.path.join(DATA_DIR, f"run_{i}.csv") for i in range(1, 11)
    ]
    originals = {path: open(path, "rb").read() for path in paths}

    def restore_inputs():
        os.makedirs(DATA_DIR, exist_ok=True)
        for path, contents in originals.items():
            with open(path, "wb") as f:
                f.write(contents)

    try:
        for accept_null in (True, False):
            write_challenge(accept_null)
            expected = calculate_expected()
            run_script()
            assert_report(expected)
    finally:
        restore_inputs()

    # Execute once more on the task's original inputs so the original report
    # assertions below validate output produced by the submitted script.
    run_script()
    restore_inputs()


def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."


def test_report_contents(expected_results):
    with open(REPORT_PATH, "r") as f:
        lines = [line.strip() for line in f.read().strip().split("\n")]

    assert len(lines) == 3, f"Expected exactly 3 lines in {REPORT_PATH}, got {len(lines)}."

    expected_baseline_line = f"Baseline Energy: {expected_results['baseline']}"
    expected_max_diff_line = f"Max Difference: {expected_results['max_diff']}"
    expected_conclusion_line = f"Conclusion: {expected_results['conclusion']}"

    assert lines[0] == expected_baseline_line, f"Line 1 mismatch. Expected '{expected_baseline_line}', got '{lines[0]}'"
    assert lines[1] == expected_max_diff_line, f"Line 2 mismatch. Expected '{expected_max_diff_line}', got '{lines[1]}'"
    assert lines[2] == expected_conclusion_line, f"Line 3 mismatch. Expected '{expected_conclusion_line}', got '{lines[2]}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
