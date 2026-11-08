#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_output_file_exists():
    """Verify that the output file was created."""
    file_path = "/home/user/top_singular_values.csv"
    assert os.path.isfile(file_path), f"Output file {file_path} does not exist."

def test_output_file_content():
    """Verify that the output file contains the correct top 3 singular values."""
    file_path = "/home/user/top_singular_values.csv"
    assert os.path.isfile(file_path), f"Output file {file_path} does not exist."

    with open(file_path, 'r') as f:
        content = f.read().strip()

    expected_content = "152.0294,147.2891,142.1009"
    assert content == expected_content, (
        f"Output file content is incorrect.\n"
        f"Expected: '{expected_content}'\n"
        f"Got:      '{content}'"
    )

def test_output_file_format():
    """Verify that the output file has exactly one line with comma-separated values."""
    file_path = "/home/user/top_singular_values.csv"
    if not os.path.isfile(file_path):
        pytest.skip(f"Output file {file_path} missing.")

    with open(file_path, 'r') as f:
        lines = f.readlines()

    # Ignore empty trailing lines
    non_empty_lines = [line for line in lines if line.strip()]
    assert len(non_empty_lines) == 1, f"Expected exactly 1 line of output, got {len(non_empty_lines)} lines."

    parts = non_empty_lines[0].strip().split(',')
    assert len(parts) == 3, f"Expected 3 comma-separated values, got {len(parts)}."

    for val in parts:
        try:
            float(val)
        except ValueError:
            pytest.fail(f"Value '{val}' is not a valid number.")

        # Check if it has exactly 4 decimal places
        if '.' in val:
            decimals = val.split('.')[1]
            assert len(decimals) == 4, f"Value '{val}' is not rounded to exactly 4 decimal places."
        else:
            pytest.fail(f"Value '{val}' does not have decimal places.")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
