#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess

import pytest
from scipy.stats import wasserstein_distance

SCRIPT_PATH = "/home/user/evaluate_perf.sh"
BASELINE_PATH = "/home/user/baseline_latencies.txt"
NEW_PATH = "/home/user/new_latencies.txt"


def run_script():
    try:
        return subprocess.run(
            [SCRIPT_PATH],
            capture_output=True,
            text=True,
            check=True,
            timeout=20,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"Script execution failed with exit code {e.returncode}. Stderr: {e.stderr}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Script execution timed out")


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_script_output():
    result = run_script()
    output = result.stdout.strip().split('\n')

    expected_output = [
        "Baseline p99: 45.15",
        "New p99: 70.13",
        "Wasserstein: 5.42",
        "Regression: YES",
    ]

    assert len(output) == 4, f"Expected 4 lines of output, got {len(output)}: {output}"

    for i, (actual, expected) in enumerate(zip(output, expected_output)):
        assert actual.strip() == expected, (
            f"Line {i+1} mismatch. Expected '{expected}', got '{actual.strip()}'"
        )


def write_dataset(path, values):
    # Return the exact values represented in the file so expected results are
    # calculated from precisely the same inputs supplied to the submission.
    rendered = [f"{value:.6f}" for value in values]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(rendered) + "\n")
    return [float(value) for value in rendered]


def expected_output(baseline, new):
    baseline_mean = sum(baseline) / len(baseline)
    new_mean = sum(new) / len(new)
    baseline_p99 = baseline_mean * math.log(100.0)
    new_p99 = new_mean * math.log(100.0)
    distance = float(wasserstein_distance(baseline, new))
    regression = new_p99 > baseline_p99 and distance > 2.00
    return [
        f"Baseline p99: {baseline_p99:.2f}",
        f"New p99: {new_p99:.2f}",
        f"Wasserstein: {distance:.2f}",
        f"Regression: {'YES' if regression else 'NO'}",
    ]


def test_script_recomputes_for_varied_datasets():
    with open(BASELINE_PATH, "rb") as f:
        original_baseline = f.read()
    with open(NEW_PATH, "rb") as f:
        original_new = f.read()

    rng = secrets.SystemRandom()
    base = [rng.uniform(8.0, 18.0) for _ in range(11)]
    cases = [
        # Higher fitted p99 and distance above the threshold: YES.
        (base, [x + rng.uniform(3.1, 4.2) for x in base]),
        # Higher fitted p99 but distance below the threshold: NO.
        (base, [x + rng.uniform(0.4, 0.9) for x in base]),
        # Distance above the threshold but lower fitted p99: NO.
        (base, [x - rng.uniform(3.0, 4.0) for x in base]),
        # Equal means but substantially different empirical distributions: NO.
        ([1.0, 1.0, 1.0, 13.0], [4.0, 4.0, 4.0, 4.0]),
        # Unequal sample sizes exercise the empirical Wasserstein calculation.
        ([2.3, 4.7, 8.1, 11.4, 17.2], [3.0, 6.2, 9.8, 14.5, 18.9, 22.1, 27.4]),
    ]

    try:
        for baseline_values, new_values in cases:
            baseline = write_dataset(BASELINE_PATH, baseline_values)
            new = write_dataset(NEW_PATH, new_values)
            expected = expected_output(baseline, new)

            result = run_script()
            actual = result.stdout.strip().split("\n")
            assert len(actual) == 4, (
                f"Expected 4 lines of output, got {len(actual)}: {actual}"
            )
            for i, (actual_line, expected_line) in enumerate(zip(actual, expected)):
                assert actual_line.strip() == expected_line, (
                    f"Varied-input line {i+1} mismatch. Expected "
                    f"'{expected_line}', got '{actual_line.strip()}'"
                )
    finally:
        with open(BASELINE_PATH, "wb") as f:
            f.write(original_baseline)
        with open(NEW_PATH, "wb") as f:
            f.write(original_new)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
