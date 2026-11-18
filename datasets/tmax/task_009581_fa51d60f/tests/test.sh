#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_trace_file_exists():
    """Test that the trace.txt file exists."""
    trace_path = "/home/user/trace.txt"
    assert os.path.isfile(trace_path), f"Missing file: {trace_path}. The script did not create the expected output file."

def test_trace_file_content():
    """Test that the trace.txt file contains the correctly computed trace value."""
    trace_path = "/home/user/trace.txt"

    # We only check content if the file exists
    if not os.path.isfile(trace_path):
        pytest.fail(f"Cannot check content because {trace_path} does not exist.")

    with open(trace_path, "r") as f:
        content = f.read().strip()

    expected_value = "14.6190"

    assert content == expected_value, f"Incorrect trace value in {trace_path}. Expected '{expected_value}', but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
