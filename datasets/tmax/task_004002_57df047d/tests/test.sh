#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import glob
import os
import math
from collections import Counter
import pytest

POOLED_FILE = "/home/user/pooled_preds.csv"
BOOTSTRAP_FILE = "/home/user/bootstrap_sample.csv"
REPORT_FILE = "/home/user/report.txt"
EXPECTED_POOL = Counter({"0,0": 5, "0,1": 2, "1,0": 2, "1,1": 6})

def expected_pool_from_experiments():
    pooled = []
    for path in sorted(glob.glob("/home/user/experiments/run_*/predictions.csv")):
        with open(path, "r") as f:
            lines = [line.strip() for line in f if line.strip()]

        assert lines and lines[0] == "true_label,prediction", \
            f"Unexpected or missing header in source file {path}"

        rows = lines[1:]
        valid_run = bool(rows) and all(
            len(row.split(',')) == 2 and row.split(',')[1] in {"0", "1"}
            for row in rows
        )
        if valid_run:
            pooled.extend(rows)

    source_pool = Counter(pooled)
    assert source_pool == EXPECTED_POOL, \
        "The source experiment files were unexpectedly modified"
    return source_pool

def test_pooled_preds_file():
    assert os.path.exists(POOLED_FILE), f"File not found: {POOLED_FILE}"

    with open(POOLED_FILE, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 15, f"Expected exactly 15 lines in {POOLED_FILE}, but got {len(lines)}"

    valid_patterns = {"0,0", "0,1", "1,0", "1,1"}
    for i, line in enumerate(lines):
        assert line in valid_patterns, f"Invalid data on line {i+1} of {POOLED_FILE}: '{line}'. Only '0,0', '0,1', '1,0', and '1,1' are allowed."

    expected = expected_pool_from_experiments()
    actual = Counter(lines)
    assert actual == expected, \
        f"{POOLED_FILE} does not contain exactly the rows from all valid classification runs. Expected {expected}, got {actual}."

def test_bootstrap_sample_file():
    assert os.path.exists(BOOTSTRAP_FILE), f"File not found: {BOOTSTRAP_FILE}"

    with open(BOOTSTRAP_FILE, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 500, f"Expected exactly 500 lines in {BOOTSTRAP_FILE}, but got {len(lines)}"

    valid_patterns = {"0,0", "0,1", "1,0", "1,1"}
    for i, line in enumerate(lines):
        assert line in valid_patterns, f"Invalid data on line {i+1} of {BOOTSTRAP_FILE}: '{line}'. Only '0,0', '0,1', '1,0', and '1,1' are allowed."

def test_evaluate_and_report():
    assert os.path.exists(BOOTSTRAP_FILE), f"Cannot evaluate accuracy because {BOOTSTRAP_FILE} is missing."
    assert os.path.exists(REPORT_FILE), f"File not found: {REPORT_FILE}"

    with open(BOOTSTRAP_FILE, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, f"{BOOTSTRAP_FILE} is empty, cannot compute accuracy."

    correct_count = 0
    for line in lines:
        parts = line.split(',')
        if len(parts) == 2 and parts[0] == parts[1]:
            correct_count += 1

    expected_accuracy = correct_count / len(lines)

    with open(REPORT_FILE, 'r') as f:
        report_content = f.read().strip()

    try:
        reported_accuracy = float(report_content)
    except ValueError:
        pytest.fail(f"Could not parse a float from {REPORT_FILE}. Content was: '{report_content}'")

    assert math.isclose(reported_accuracy, expected_accuracy, rel_tol=1e-5, abs_tol=1e-5), \
        f"Reported accuracy {reported_accuracy} does not match the expected accuracy {expected_accuracy} calculated from {BOOTSTRAP_FILE}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
