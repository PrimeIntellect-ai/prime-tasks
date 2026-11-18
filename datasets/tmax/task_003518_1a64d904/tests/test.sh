#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import statistics
import pytest

def test_process_cpp_exists():
    cpp_path = "/home/user/analysis/process.cpp"
    assert os.path.isfile(cpp_path), f"The C++ source file {cpp_path} does not exist."

def test_bootstrap_means_exists():
    output_path = "/home/user/analysis/bootstrap_means.csv"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."

def test_bootstrap_means_content():
    dataset_path = '/home/user/dataset.csv'
    assert os.path.isfile(dataset_path), f"Dataset file is missing: {dataset_path}"

    # 1. Read dataset
    data = []
    with open(dataset_path, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            data.append([float(x) for x in row])

    assert len(data) == 50, "Dataset should have 50 rows."

    cols = list(zip(*data))

    # 2. Compute variance and find top 3
    variances = [statistics.variance(col) for col in cols]
    top_3_indices = sorted(sorted(range(len(variances)), key=lambda i: variances[i], reverse=True)[:3])

    reduced_data = []
    for row in data:
        reduced_data.append([row[i] for i in top_3_indices])

    # 3. Bootstrap with LCG
    state = 42
    def lcg():
        nonlocal state
        state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
        return state

    expected_lines = []
    for _ in range(1000):
        sample_sums = [0.0, 0.0, 0.0]
        for _ in range(50):
            idx = lcg() % 50
            sample_sums[0] += reduced_data[idx][0]
            sample_sums[1] += reduced_data[idx][1]
            sample_sums[2] += reduced_data[idx][2]

        expected_lines.append(f"{sample_sums[0]/50:.4f},{sample_sums[1]/50:.4f},{sample_sums[2]/50:.4f}")

    # 4. Compare with actual output
    output_path = '/home/user/analysis/bootstrap_means.csv'
    with open(output_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == 1000, f"Expected 1000 rows in output, got {len(actual_lines)}"

    for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
        assert expected == actual, f"Mismatch at row {i+1}. Expected: {expected}, Actual: {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
