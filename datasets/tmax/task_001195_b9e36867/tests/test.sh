#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import csv
import math
import os
import pytest


def test_clean_calibration_csv():
    file_path = "/home/user/clean_calibration.csv"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."

    expected_header = ["x", "y", "status"]
    expected_rows = [
        (1.0, 2.2, "valid"),
        (2.0, 4.1, "valid"),
        (3.0, 6.0, "valid"),
        (6.0, 12.1, "valid"),
    ]

    with open(file_path, "r", newline="") as f:
        content = list(csv.reader(f))

    assert len(content) == len(expected_rows) + 1, (
        f"Expected {len(expected_rows) + 1} CSV records in {file_path}, "
        f"found {len(content)}."
    )
    assert content[0] == expected_header, (
        f"Header in {file_path} is incorrect. Expected {expected_header}, "
        f"got {content[0]}."
    )

    for i, (actual, expected) in enumerate(zip(content[1:], expected_rows), start=2):
        assert len(actual) == 3, f"CSV record {i} must contain exactly 3 fields."
        try:
            actual_x = float(actual[0])
            actual_y = float(actual[1])
        except ValueError:
            pytest.fail(f"CSV record {i} has a non-numeric x or y value: {actual!r}")

        assert math.isfinite(actual_x) and math.isfinite(actual_y), (
            f"CSV record {i} has a non-finite x or y value: {actual!r}"
        )
        assert actual_x == expected[0], (
            f"CSV record {i} has incorrect x. Expected {expected[0]}, got {actual[0]!r}."
        )
        assert actual_y == expected[1], (
            f"CSV record {i} has incorrect y. Expected {expected[1]}, got {actual[1]!r}."
        )
        assert actual[2] == expected[2], (
            f"CSV record {i} has incorrect status. Expected {expected[2]!r}, got {actual[2]!r}."
        )


def test_report_txt():
    file_path = "/home/user/report.txt"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."

    expected_lines = [
        "1.9857",
        "0.1429",
        "0.0571"
    ]

    with open(file_path, "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) == 3, f"Expected exactly 3 lines in {file_path}, found {len(content)}."

    labels = ["Slope (m)", "Y-intercept (b)", "Mean Absolute Error (MAE)"]
    for i, (actual, expected, label) in enumerate(zip(content, expected_lines, labels)):
        actual_val = actual.strip()
        assert actual_val == expected, f"{label} on line {i+1} is incorrect. Expected '{expected}', got '{actual_val}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
