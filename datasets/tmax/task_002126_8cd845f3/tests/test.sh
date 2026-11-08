#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_report_json_exists():
    """Test that the report.json file exists."""
    report_file = "/home/user/incident/report.json"
    assert os.path.isfile(report_file), f"File {report_file} is missing. Did you create the report?"

def test_report_json_content():
    """Test that the report.json file contains the correct extracted values."""
    report_file = "/home/user/incident/report.json"
    assert os.path.isfile(report_file), "report.json is missing."

    with open(report_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("report.json is not a valid JSON file.")

    expected_md5_file = "/tests/.expected_md5"
    assert os.path.isfile(expected_md5_file), "Expected MD5 oracle is missing from the test environment."

    with open(expected_md5_file, 'r') as f:
        expected_md5 = f.read().strip()

    assert "intended_upload_path" in data, "Key 'intended_upload_path' is missing from report.json."
    assert data["intended_upload_path"] == "../../../../../var/www/html/uploads/system_update", \
        "Incorrect 'intended_upload_path' in report.json."

    assert "privesc_target" in data, "Key 'privesc_target' is missing from report.json."
    assert data["privesc_target"] == "/usr/local/sbin/vuln_backup_manager", \
        "Incorrect 'privesc_target' in report.json."

    assert "payload_md5" in data, "Key 'payload_md5' is missing from report.json."
    assert data["payload_md5"] == expected_md5, \
        "Incorrect 'payload_md5' in report.json."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
