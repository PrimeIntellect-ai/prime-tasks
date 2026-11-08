#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_tracker_cpp_exists():
    """Verify that the C++ source file exists."""
    assert os.path.isfile("/home/user/tracker.cpp"), "/home/user/tracker.cpp does not exist."

def test_tracker_executable_exists():
    """Verify that the compiled executable exists."""
    assert os.path.isfile("/home/user/tracker"), "/home/user/tracker executable does not exist."
    assert os.access("/home/user/tracker", os.X_OK), "/home/user/tracker is not executable."

def test_summary_txt_correct():
    """Verify that the summary.txt file contains the correct output."""
    summary_path = "/home/user/summary.txt"
    assert os.path.isfile(summary_path), f"{summary_path} does not exist."

    expected_content = """--- app_settings.conf ---
port=8080
host=localhost
env=production
--- network.conf ---
ip=192.168.1.1
subnet=255.255.255.0
"""

    with open(summary_path, "r", encoding="utf-8") as f:
        actual_content = f.read()

    # Normalize line endings for comparison
    actual_normalized = actual_content.strip().replace("\r\n", "\n")
    expected_normalized = expected_content.strip().replace("\r\n", "\n")

    assert actual_normalized == expected_normalized, f"The content of {summary_path} does not match the expected output. Got:\n{actual_content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
