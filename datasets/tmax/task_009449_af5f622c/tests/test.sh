#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import re
import pytest

def is_strict_numeric(val):
    """
    Checks if a string is strictly numeric (allows negative signs and decimal points, but no other characters).
    """
    return bool(re.match(r"^-?\d+(\.\d+)?$", val))

def get_expected_data():
    """
    Derives the expected header, valid rows, and feature mean based on the rules applied to the input file.
    """
    input_file = "/home/user/server_metrics.csv"
    assert os.path.exists(input_file), f"Original input file {input_file} is missing. Cannot derive expected state."

    expected_rows = []
    ratios = []

    with open(input_file, "r") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"Input file {input_file} is empty.")

        expected_header = header + ["mem_cpu_ratio"]

        for row in reader:
            # 1. Schema Enforcement: Exactly 5 columns
            if len(row) != 5:
                continue

            # 1. Schema Enforcement: Columns 2, 3, 4, 5 strictly numeric
            if not all(is_strict_numeric(x) for x in row[1:5]):
                continue

            cpu = float(row[1])
            mem = float(row[2])
            temp = float(row[4])

            # 3. Feature Selection: temp strictly greater than 40.0
            if temp <= 40.0:
                continue

            # 2. Feature Engineering: mem_cpu_ratio
            if cpu == 0.0:
                ratio_str = "0.00"
            else:
                # Format to exactly 2 decimal places
                ratio_str = f"{mem / cpu:.2f}"

            expected_rows.append(row + [ratio_str])
            ratios.append(float(ratio_str))

    mean_val = sum(ratios) / len(ratios) if ratios else 0.0
    return expected_header, expected_rows, mean_val

def test_cleaned_metrics_csv():
    output_file = "/home/user/cleaned_metrics.csv"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."

    expected_header, expected_rows, _ = get_expected_data()

    with open(output_file, "r") as f:
        reader = csv.reader(f)
        try:
            actual_header = next(reader)
        except StopIteration:
            pytest.fail(f"Cleaned metrics file {output_file} is empty.")

        assert actual_header == expected_header, f"Header mismatch in {output_file}. Expected {expected_header}, got {actual_header}"

        actual_rows = list(reader)

        assert len(actual_rows) == len(expected_rows), f"Row count mismatch in {output_file}. Expected {len(expected_rows)} valid rows, but found {len(actual_rows)}."

        for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
            assert actual == expected, f"Data mismatch at row {i+1} (excluding header). Expected {expected}, got {actual}."

def test_feature_mean_txt():
    mean_file = "/home/user/feature_mean.txt"
    assert os.path.exists(mean_file), f"Mean output file {mean_file} does not exist."

    _, _, expected_mean = get_expected_data()

    with open(mean_file, "r") as f:
        content = f.read().strip()

    assert is_strict_numeric(content), f"Content of {mean_file} ('{content}') is not strictly numeric."

    actual_mean = float(content)

    # Allow for slight differences in rounding (e.g., standard awk rounding vs python rounding)
    # For example, 27.685 might round to 27.68 or 27.69.
    assert abs(actual_mean - expected_mean) <= 0.015, f"Mean value mismatch in {mean_file}. Expected a value around {expected_mean:.2f}, got {actual_mean}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
