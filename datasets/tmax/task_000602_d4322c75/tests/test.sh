#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import importlib.util

def test_leak_report():
    report_path = "/home/user/leak_report.txt"
    assert os.path.isfile(report_path), f"File {report_path} does not exist."

    with open(report_path, 'r') as f:
        content = f.read().strip()

    expected_string = "TEL_8472|2023-11-01T15:30:00|ERROR_CODE_99: malformed_payload_data"
    assert content == expected_string, f"Incorrect content in {report_path}. Expected '{expected_string}', got '{content}'."

def test_mre_input():
    mre_path = "/home/user/mre_input.txt"
    assert os.path.isfile(mre_path), f"File {mre_path} does not exist."

    with open(mre_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {mre_path}, found {len(lines)}."

    for i, line in enumerate(lines):
        assert "ERROR_CODE_99" in line, f"Line {i+1} in {mre_path} does not contain 'ERROR_CODE_99'."
        parts = line.split('|')
        assert len(parts) == 3, f"Line {i+1} in {mre_path} is not a valid three-field telemetry record."
        assert all(part.strip() for part in parts), f"Line {i+1} in {mre_path} contains an empty telemetry field."
        assert "ERROR_CODE_99" in parts[2], f"Line {i+1} in {mre_path} does not place 'ERROR_CODE_99' in the data field."

def test_process_telemetry_fix():
    script_path = "/home/user/process_telemetry.py"
    mre_path = "/home/user/mre_input.txt"

    assert os.path.isfile(script_path), f"File {script_path} does not exist."
    assert os.path.isfile(mre_path), f"File {mre_path} does not exist."

    # Dynamically import the script
    spec = importlib.util.spec_from_file_location("process_telemetry", script_path)
    process_telemetry = importlib.util.module_from_spec(spec)
    sys.modules["process_telemetry"] = process_telemetry

    try:
        spec.loader.exec_module(process_telemetry)
    except Exception as e:
        assert False, f"Failed to import {script_path} due to syntax or execution error: {e}"

    assert hasattr(process_telemetry, "parse_telemetry"), "parse_telemetry function is missing."
    assert hasattr(process_telemetry, "_error_cache"), "_error_cache is missing."

    # Clear cache just in case
    process_telemetry._error_cache = []

    try:
        process_telemetry.parse_telemetry(mre_path)
    except Exception as e:
        assert False, f"parse_telemetry threw an exception when processing {mre_path}: {e}"

    assert len(process_telemetry._error_cache) == 0, f"The memory leak is not fixed. _error_cache contains {len(process_telemetry._error_cache)} items after processing MRE."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
