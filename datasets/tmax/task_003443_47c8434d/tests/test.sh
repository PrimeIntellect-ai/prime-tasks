#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

def test_executable_compiled_with_debug_symbols():
    exe_path = "/home/user/log_transformer"
    assert os.path.exists(exe_path), f"Executable {exe_path} does not exist. Did you compile the C program?"
    assert os.path.isfile(exe_path), f"{exe_path} is not a file."
    assert os.access(exe_path, os.X_OK), f"{exe_path} is not executable."

    # Check for debug symbols using 'file' or 'objdump' or 'nm' or 'readelf'
    # 'readelf -S' will list sections. We look for '.debug_info'
    result = subprocess.run(['readelf', '-S', exe_path], capture_output=True, text=True)
    assert ".debug_info" in result.stdout, f"Executable {exe_path} does not appear to have debugging symbols enabled (e.g., compiled with -g)."

def test_diagnostic_report_content():
    report_path = "/home/user/diagnostic_report.txt"
    assert os.path.exists(report_path), f"Report file {report_path} does not exist."
    assert os.path.isfile(report_path), f"{report_path} is not a file."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 non-empty lines in {report_path}, found {len(lines)}."

    expected_line1 = "Function: process_line"
    expected_line2 = "Crashing Input: 2023-10-25T08:14:05Z FATAL Out of memory in main thread"
    expected_line3 = 'Preceding Output: {"timestamp":"2023-10-25T08:14:02Z", "level":"DEBUG", "message":"Connection established to backend database", "msg_len":42}'

    assert lines[0] == expected_line1, f"Line 1 is incorrect. Expected '{expected_line1}', got '{lines[0]}'."
    assert lines[1] == expected_line2, f"Line 2 is incorrect. Expected '{expected_line2}', got '{lines[1]}'."
    assert lines[2] == expected_line3, f"Line 3 is incorrect. Expected '{expected_line3}', got '{lines[2]}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
