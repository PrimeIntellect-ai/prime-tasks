#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_extractor_compiled():
    extractor_path = "/home/user/src/extractor"
    assert os.path.isfile(extractor_path), f"Compiled executable {extractor_path} is missing."
    assert os.access(extractor_path, os.X_OK), f"File {extractor_path} is not executable."

def test_jsd_output_exists():
    output_path = "/home/user/jsd_output.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

def test_jsd_output_content():
    output_path = "/home/user/jsd_output.txt"
    with open(output_path, 'r') as f:
        content = f.read().strip()

    assert content != "", f"Output file {output_path} is empty."

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Content of {output_path} is not a valid float: '{content}'")

    expected_val = 0.2330

    # Check if it's formatted to exactly 4 decimal places
    assert "." in content and len(content.split(".")[1]) == 4, f"Output '{content}' is not formatted to exactly 4 decimal places."

    # Check if the value is correct
    assert abs(val - expected_val) < 1e-4, f"Expected JSD value close to {expected_val}, but got {val}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
