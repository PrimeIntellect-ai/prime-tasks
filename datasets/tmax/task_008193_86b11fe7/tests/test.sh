#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_output_file_exists():
    """Test that the output file was created."""
    file_path = "/home/user/clean_normalized.csv"
    assert os.path.exists(file_path), f"The output file {file_path} was not created."
    assert os.path.isfile(file_path), f"The path {file_path} is not a regular file."

def test_output_file_contents():
    """Test that the output file contains the correct cleaned, imputed, and normalized data."""
    file_path = "/home/user/clean_normalized.csv"

    expected_lines = [
        "timestamp,normalized_temp",
        "2023-10-01T10:00:00Z,0.0000",
        "2023-10-01T11:00:00Z,0.2500",
        "2023-10-01T12:00:00Z,0.2500",
        "2023-10-01T14:00:00Z,0.5000",
        "2023-10-01T15:00:00Z,1.0000",
        "2023-10-01T16:00:00Z,1.0000",
        "2023-10-01T18:00:00Z,1.0000"
    ]

    with open(file_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"The contents of {file_path} do not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )

def test_output_formatting():
    """Test that the output values strictly follow the 4 decimal places rule."""
    file_path = "/home/user/clean_normalized.csv"

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    # Skip header
    data_lines = lines[1:]
    for line in data_lines:
        parts = line.split(",")
        assert len(parts) == 2, f"Line '{line}' does not have exactly 2 comma-separated columns."
        temp_str = parts[1]

        # Check if there's exactly a dot and 4 digits after it
        assert "." in temp_str, f"Temperature '{temp_str}' is missing a decimal point."
        decimals = temp_str.split(".")[1]
        assert len(decimals) == 4, f"Temperature '{temp_str}' does not have exactly 4 decimal places."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
