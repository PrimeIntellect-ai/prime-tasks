#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import sys
import pytest

def get_expected_csv_content():
    """
    Uses a subprocess to run pandas (which is available in the environment)
    to compute the expected exact output, ensuring we match the numpy/pandas 
    PRNG behavior for random_state=42.
    """
    script = """
import pandas as pd
df = pd.read_csv('/home/user/inference_data.csv')
df['prediction_score'] = pd.to_numeric(df['prediction_score'], errors='coerce')
clean_df = df[
    (df['label'].isin(['A', 'B'])) & 
    (df['prediction_score'] >= 0.0) & 
    (df['prediction_score'] <= 1.0)
].copy()
sample_df = clean_df.sample(n=50, replace=True, random_state=42)
print(sample_df.to_csv(index=False))
"""
    result = subprocess.run(
        [sys.executable, "-c", script],
        capture_output=True,
        text=True,
        check=True
    )
    return result.stdout.strip()

def test_bootstrapped_file_exists():
    """Check that the final output file exists."""
    output_file = "/home/user/bootstrapped_clean.csv"
    assert os.path.exists(output_file), f"The output file {output_file} does not exist."
    assert os.path.isfile(output_file), f"The path {output_file} is not a file."

def test_bootstrapped_file_content():
    """Check that the final output file matches the expected bootstrapped sample."""
    output_file = "/home/user/bootstrapped_clean.csv"

    with open(output_file, "r") as f:
        student_content = f.read().strip()

    expected_content = get_expected_csv_content()

    student_lines = student_content.splitlines()
    expected_lines = expected_content.splitlines()

    assert len(student_lines) == len(expected_lines), (
        f"Row count mismatch. Expected {len(expected_lines)} lines (including header), "
        f"but got {len(student_lines)}."
    )

    for i, (s_line, e_line) in enumerate(zip(student_lines, expected_lines)):
        assert s_line == e_line, (
            f"Mismatch at line {i + 1}.\n"
            f"Expected: {e_line}\n"
            f"Got:      {s_line}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
