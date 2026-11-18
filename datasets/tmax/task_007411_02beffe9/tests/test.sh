#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import math
import os
import re
import subprocess
import pytest

OUTPUT_PATHS = [
    "/home/user/mc_results.txt",
    "/home/user/variance.txt",
    "/home/user/stability.log",
    "/home/user/histogram.txt",
]

@pytest.fixture(scope="module", autouse=True)
def run_submission_from_scratch():
    script_path = "/home/user/mc_sensor.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    with open(script_path, "r", errors="replace") as f:
        script = f.read()
    assert re.search(r"(^|[^A-Za-z0-9_])awk([^A-Za-z0-9_]|$)", script), \
        "The simulation script must use awk."
    assert re.search(r"srand\s*\(\s*42\s*\)", script), \
        "The awk simulation must call srand(42)."

    for path in OUTPUT_PATHS:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    completed = subprocess.run(
        [script_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"mc_sensor.sh exited with status {completed.returncode}. "
        f"stderr: {completed.stderr}"
    )


def test_script_exists_and_executable():
    script_path = "/home/user/mc_sensor.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_mc_results():
    results_path = "/home/user/mc_results.txt"
    assert os.path.isfile(results_path), f"Results file {results_path} does not exist."
    with open(results_path, 'r') as f:
        lines = f.read().splitlines()
    assert len(lines) == 1000, f"Expected 1000 lines in {results_path}, got {len(lines)}."

    # Check if all lines are floats
    values = []
    for i, line in enumerate(lines):
        try:
            value = float(line)
        except ValueError:
            pytest.fail(f"Line {i+1} in {results_path} is not a valid float: '{line}'")
        assert math.isfinite(value), f"Line {i+1} is not finite: '{line}'"
        values.append(value)

    oracle_program = r'''BEGIN {
        srand(42)
        for (i = 1; i <= 1000; i++) {
            sum = 0
            for (j = 1; j <= 100; j++) {
                sum += 2 * rand() - 1
            }
            print sum
        }
    }'''
    oracle = subprocess.run(
        ["/usr/bin/gawk", oracle_program],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    expected = [float(line) for line in oracle.stdout.splitlines()]
    assert len(expected) == 1000
    for i, (actual, wanted) in enumerate(zip(values, expected), 1):
        assert math.isclose(actual, wanted, rel_tol=0.0, abs_tol=1e-4), (
            f"Monte Carlo reading {i} does not match the value produced by "
            f"srand(42) and 100 uniform awk steps: expected {wanted}, got {actual}."
        )


def test_variance():
    results_path = "/home/user/mc_results.txt"
    variance_path = "/home/user/variance.txt"

    assert os.path.isfile(results_path), "Missing mc_results.txt"
    assert os.path.isfile(variance_path), f"Variance file {variance_path} does not exist."

    with open(results_path, 'r') as f:
        values = [float(line) for line in f.read().splitlines()]

    n = len(values)
    mean = sum(values) / n
    variance = sum((x - mean) ** 2 for x in values) / (n - 1)
    expected_variance_str = f"{variance:.2f}"

    with open(variance_path, 'r') as f:
        actual_variance_str = f.read().strip()

    assert actual_variance_str == expected_variance_str, f"Expected variance {expected_variance_str}, got {actual_variance_str}."


def test_stability_log():
    variance_path = "/home/user/variance.txt"
    stability_path = "/home/user/stability.log"

    assert os.path.isfile(variance_path), "Missing variance.txt"
    assert os.path.isfile(stability_path), f"Stability log {stability_path} does not exist."

    with open(variance_path, 'r') as f:
        variance = float(f.read().strip())

    expected_status = "STABLE" if 25.00 < variance < 40.00 else "UNSTABLE"

    with open(stability_path, 'r') as f:
        actual_status = f.read().strip()

    assert actual_status == expected_status, f"Expected stability log to be {expected_status}, got {actual_status}."


def test_histogram():
    results_path = "/home/user/mc_results.txt"
    histogram_path = "/home/user/histogram.txt"

    assert os.path.isfile(results_path), "Missing mc_results.txt"
    assert os.path.isfile(histogram_path), f"Histogram file {histogram_path} does not exist."

    with open(results_path, 'r') as f:
        values = [float(line) for line in f.read().splitlines()]

    bins = [0] * 8
    for val in values:
        if -20 <= val < -15: bins[0] += 1
        elif -15 <= val < -10: bins[1] += 1
        elif -10 <= val < -5: bins[2] += 1
        elif -5 <= val < 0: bins[3] += 1
        elif 0 <= val < 5: bins[4] += 1
        elif 5 <= val < 10: bins[5] += 1
        elif 10 <= val < 15: bins[6] += 1
        elif 15 <= val <= 20: bins[7] += 1

    centers = [-17.5, -12.5, -7.5, -2.5, 2.5, 7.5, 12.5, 17.5]
    expected_lines = []
    for center, count in zip(centers, bins):
        stars = "*" * (count // 10)
        expected_lines.append(f"{center:.1f} |{stars}")

    with open(histogram_path, 'r') as f:
        actual_lines = f.read().splitlines()

    assert len(actual_lines) == 8, f"Expected 8 lines in {histogram_path}, got {len(actual_lines)}."

    for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
        assert actual == expected, f"Histogram mismatch on line {i+1}: expected '{expected}', got '{actual}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
