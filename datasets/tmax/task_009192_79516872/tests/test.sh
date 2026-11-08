#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_final_report_exists_and_content():
    """Test that the final report is generated correctly with the expected content and encoding."""
    expected_output = """# Daily Event Report
**Date:** 2023-10-25
**Total Events:** 3

## Event Log
- [13:20:00] LOGIN: user logged in from café
- [14:30:00] ERROR: disk full 99 usage
- [15:45:00] LOGOUT: el niño logged out"""

    filepath = "/home/user/output/report_2023-10-25.md"

    assert os.path.exists(filepath), f"Expected output file not found: {filepath}"

    try:
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read().strip()
    except UnicodeDecodeError:
        pytest.fail(f"File {filepath} is not correctly encoded in UTF-8.")

    assert content == expected_output.strip(), (
        f"Content of {filepath} does not match expected output.\n"
        f"Got:\n{content}\n\n"
        f"Expected:\n{expected_output.strip()}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
