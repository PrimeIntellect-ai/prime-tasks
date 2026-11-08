#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import re
import subprocess
from decimal import Decimal

import pytest

SCRIPT_PATH = "/home/user/calc_energy.sh"
FEATURES_PATH = "/home/user/features.txt"
VALIDATION_PATH = "/home/user/validation.txt"


def compute_expected_features():
    results = []
    graph_files = glob.glob("/home/user/graphs/graph_*.txt")
    for file_path in graph_files:
        filename = os.path.basename(file_path)
        name, _ = os.path.splitext(filename)
        with open(file_path, "r") as f:
            weights = [float(line.strip().split()[2]) for line in f if line.strip()]

        # Sort strictly ascending.
        weights.sort()

        # Sequential summation to match awk.
        total = 0.0
        for w in weights:
            total += w

        results.append((name, total))

    # Sort alphabetically by filename.
    results.sort(key=lambda x: x[0])
    return results


def test_00_calc_energy_script_exists_and_runs():
    """Check that the executable Bash artifact itself generates fresh outputs."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").strip()
    assert first_line.startswith("#!") and "bash" in first_line, \
        f"Script {SCRIPT_PATH} must be a Bash script."

    # Hidden-at-authoring-time inputs make stale or hard-coded output insufficient.
    probes = {
        "/home/user/graphs/graph_verifier_order.txt": (
            "0 1 10000000000000000\n"
            "0 2 -10000000000000000\n"
            "0 3 1\n"
        ),
        "/home/user/graphs/graph_verifier_numeric.txt": (
            "0 1 10000000000000000\n"
            "0 2 -10000000000000000\n"
            "0 3 -10\n"
            "0 4 -2\n"
            "0 5 -1\n"
        ),
    }
    for path, content in probes.items():
        with open(path, "w") as f:
            f.write(content)

    graph_contents = {}
    for path in glob.glob("/home/user/graphs/graph_*.txt"):
        with open(path, "rb") as f:
            graph_contents[path] = f.read()

    for path in (FEATURES_PATH, VALIDATION_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    completed = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(FEATURES_PATH), \
        f"Running {SCRIPT_PATH} did not create {FEATURES_PATH}."
    assert os.path.isfile(VALIDATION_PATH), \
        f"Running {SCRIPT_PATH} did not create {VALIDATION_PATH}."

    # The script must process, not remove or alter, every graph supplied to it.
    for path, original in graph_contents.items():
        assert os.path.isfile(path), f"Running the script removed input graph {path}."
        with open(path, "rb") as f:
            assert f.read() == original, f"Running the script modified input graph {path}."


def test_features_file_correctness():
    """Check if features.txt contains the correctly ordered and formatted sums."""
    assert os.path.isfile(FEATURES_PATH), f"Output file {FEATURES_PATH} is missing."

    expected_results = compute_expected_features()

    with open(FEATURES_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_results), \
        f"Expected {len(expected_results)} lines in {FEATURES_PATH}, found {len(lines)}."

    for i, (expected_name, expected_total) in enumerate(expected_results):
        expected_line = f"{expected_name}: {expected_total:.10f}"
        assert lines[i] == expected_line, \
            f"Mismatch at line {i + 1}. Expected '{expected_line}', got '{lines[i]}'."


def test_validation_file_correctness():
    """Check the analytical difference and its requested decimal precision."""
    assert os.path.isfile(VALIDATION_PATH), \
        f"Validation file {VALIDATION_PATH} is missing."

    with open(VALIDATION_PATH, "r") as f:
        content = f.read().strip()

    match = re.fullmatch(r"(\d+)\.(\d{10,})", content)
    assert match, (
        f"Content of {VALIDATION_PATH} must be one non-negative fixed-point value "
        f"with at least 10 decimal places, got '{content}'."
    )

    try:
        diff_value = float(content)
    except ValueError:
        pytest.fail(f"Content of {VALIDATION_PATH} is not a valid float: '{content}'")

    # Preserve the original non-negative and upper-bound assertions.
    assert diff_value >= 0, f"Absolute difference cannot be negative, got {diff_value}."
    assert diff_value <= 1e-10, \
        f"Absolute difference {diff_value} is too large. Expected <= 1e-10."

    expected_results = dict(compute_expected_features())
    pipeline_energy = Decimal(f"{expected_results['graph_0']:.10f}")
    analytical_value = Decimal(1) - (Decimal(1) / (Decimal(2) ** 20))
    exact_difference = abs(pipeline_energy - analytical_value)

    decimal_places = len(match.group(2))
    quantum = Decimal(1).scaleb(-decimal_places)
    expected_at_reported_precision = exact_difference.quantize(quantum)
    actual = Decimal(content)
    assert actual == expected_at_reported_precision, (
        f"Expected the graph_0 difference rounded to {decimal_places} decimal places "
        f"to be {expected_at_reported_precision:.{decimal_places}f}, got {content}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
