#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_fit_results():
    """Check if the fit_results.txt file exists and has the correct content."""
    txt_path = "/home/user/fit_results.txt"
    assert os.path.isfile(txt_path), f"The file {txt_path} does not exist."

    with open(txt_path, 'r') as f:
        content = f.read().strip()

    expected_content = "0.50,-0.20,15.00"
    assert content == expected_content, f"Expected fit_results.txt to contain '{expected_content}', but got '{content}'."

def test_refined_mesh_csv():
    """Check if the refined_mesh.csv file exists and has the correct dimensions and values."""
    csv_path = "/home/user/refined_mesh.csv"
    assert os.path.isfile(csv_path), f"The file {csv_path} does not exist."

    with open(csv_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 21, f"Expected 21 rows in refined_mesh.csv, but got {len(lines)}."

    for i, line in enumerate(lines):
        values = line.split(',')
        assert len(values) == 21, f"Expected 21 columns in row {i}, but got {len(values)}."

        x = 20.0 + i * 0.5
        for j, val_str in enumerate(values):
            y = 40.0 + j * 0.5
            expected_temp = 0.5 * x - 0.2 * y + 15.0
            expected_str = f"{expected_temp:.4f}"

            assert val_str == expected_str, (
                f"Value mismatch at row {i}, col {j} (x={x}, y={y}). "
                f"Expected {expected_str}, got {val_str}."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
