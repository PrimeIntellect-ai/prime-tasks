#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_script_exists_and_executable():
    """Verify that the build_summary.sh script exists and is executable."""
    script_path = "/home/user/build_summary.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

def test_output_file_exists():
    """Verify that the output file max_values.tsv exists."""
    output_path = "/home/user/max_values.tsv"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."

def test_output_file_content():
    """Verify the exact content of the generated max_values.tsv file."""
    output_path = "/home/user/max_values.tsv"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."

    with open(output_path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    expected_lines = [
        "Location\tMaxValue",
        "Basement\t-2.5",
        "Lobby\t15.0",
        "Roof\t100.1"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {output_path}, but got {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{actual}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
