#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import tarfile
import pytest

def get_expected_results(backup_dir):
    expected = {}
    for filename in os.listdir(backup_dir):
        if not filename.endswith('.tar.gz'):
            continue
        filepath = os.path.join(backup_dir, filename)
        try:
            with tarfile.open(filepath, 'r:gz') as tar:
                max_depth = 0
                for member in tar.getmembers():
                    depth = member.name.count('/')
                    if depth > max_depth:
                        max_depth = depth
                expected[filename] = {
                    "status": "valid",
                    "max_depth": max_depth
                }
        except Exception:
            # Any error opening or reading the tar.gz means it's corrupt
            expected[filename] = {
                "status": "corrupt",
                "max_depth": 0
            }
    return expected

def test_report_json_exists():
    """Check that the report.json file was created."""
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"Expected report file at {report_path} does not exist."

def test_report_json_content():
    """Check that the report.json contains the correct structured data."""
    report_path = "/home/user/report.json"
    backup_dir = "/home/user/backups"

    # Ensure the file exists before checking content
    assert os.path.isfile(report_path), f"Expected report file at {report_path} does not exist."

    with open(report_path, 'r') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {report_path} does not contain valid JSON.")

    expected_data = get_expected_results(backup_dir)

    # Check that all expected keys are present and match
    for backup_file, expected_info in expected_data.items():
        assert backup_file in report_data, f"Missing entry for {backup_file} in report.json."

        actual_info = report_data[backup_file]
        assert "status" in actual_info, f"Missing 'status' key for {backup_file}."
        assert "max_depth" in actual_info, f"Missing 'max_depth' key for {backup_file}."

        assert actual_info["status"] == expected_info["status"], \
            f"Incorrect status for {backup_file}. Expected '{expected_info['status']}', got '{actual_info['status']}'."

        assert actual_info["max_depth"] == expected_info["max_depth"], \
            f"Incorrect max_depth for {backup_file}. Expected {expected_info['max_depth']}, got {actual_info['max_depth']}."

    # Check for extra keys in the report
    for backup_file in report_data:
        assert backup_file in expected_data, f"Unexpected entry for {backup_file} found in report.json."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
