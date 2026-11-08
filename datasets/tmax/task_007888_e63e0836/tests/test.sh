#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_observed_count():
    """
    Verify the observed count of the motif [0, 1, 2].
    """
    file_path = "/home/user/observed_count.txt"
    assert os.path.isfile(file_path), f"Output file missing: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == "556", f"Expected observed count to be 556, but got '{content}'"

def test_null_95():
    """
    Verify the 95th percentile of the Monte Carlo null distribution.
    """
    file_path = "/home/user/null_95.txt"
    assert os.path.isfile(file_path), f"Output file missing: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Could not parse '{content}' as a float in {file_path}")

    assert val == 604.0, f"Expected null 95th percentile to be 604.0, but got {val}"

def test_boot_ci():
    """
    Verify the 95% bootstrap confidence interval.
    """
    file_path = "/home/user/boot_ci.txt"
    assert os.path.isfile(file_path), f"Output file missing: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    parts = [p.strip() for p in content.split(",")]
    assert len(parts) == 2, f"Expected two comma-separated values in {file_path}, but got '{content}'"

    try:
        val1 = float(parts[0])
        val2 = float(parts[1])
    except ValueError:
        pytest.fail(f"Could not parse values as floats in {file_path}: '{content}'")

    assert val1 == 509.0 and val2 == 601.0, f"Expected bootstrap CI to be 509.0, 601.0, but got {val1}, {val2}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
