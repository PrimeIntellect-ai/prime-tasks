#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import pytest

def test_report_exists_and_format():
    """Verify that the report file exists and has the correct format and content."""
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"Report file not found at {report_path}"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 4, f"Expected exactly 4 non-empty lines in the report, found {len(lines)}"

    # Parse the report into a dictionary
    report_data = {}
    for line in lines:
        parts = line.split(":", 1)
        assert len(parts) == 2, f"Line format incorrect, expected 'Key: Value'. Found: {line}"
        key = parts[0].strip()
        value = parts[1].strip()
        report_data[key] = value

    # Check required keys
    expected_keys = {"Port", "Hash", "PIN", "Flag"}
    assert set(report_data.keys()) == expected_keys, f"Report must contain keys {expected_keys}. Found: {set(report_data.keys())}"

    # Verify Port (extracted from iptables.rules setup)
    assert report_data["Port"] == "8194", f"Incorrect Port. Expected 8194, found {report_data['Port']}"

    # Verify PIN
    assert report_data["PIN"] == "4829", f"Incorrect PIN. Expected 4829, found {report_data['PIN']}"

    # Verify Hash (derived from PIN)
    expected_hash = hashlib.sha256(b"4829").hexdigest()
    assert report_data["Hash"] == expected_hash, f"Incorrect Hash. Expected {expected_hash}, found {report_data['Hash']}"

    # Verify Flag (hardcoded in auth_service.c)
    expected_flag = "FLAG{3lf_4uth_byP4ss_99x}"
    assert report_data["Flag"] == expected_flag, f"Incorrect Flag. Expected {expected_flag}, found {report_data['Flag']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
