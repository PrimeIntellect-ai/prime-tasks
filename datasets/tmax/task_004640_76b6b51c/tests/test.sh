#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_incident_report_exists_and_valid():
    report_path = "/home/user/incident_report.json"
    assert os.path.isfile(report_path), f"The file {report_path} does not exist."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {report_path} does not contain valid JSON.")

    assert "sql_payload" in data, "Key 'sql_payload' is missing from the JSON report."
    assert data["sql_payload"] == "admin' OR 1=1--", "The 'sql_payload' value is incorrect."

    assert "c2_ip" in data, "Key 'c2_ip' is missing from the JSON report."
    assert data["c2_ip"] == "198.51.100.42", "The 'c2_ip' value is incorrect."

    assert "privesc_binary" in data, "Key 'privesc_binary' is missing from the JSON report."
    assert data["privesc_binary"] == "/usr/local/bin/backup_script", "The 'privesc_binary' value is incorrect."

    assert "exfil_timestamp" in data, "Key 'exfil_timestamp' is missing from the JSON report."
    assert data["exfil_timestamp"] == "2023-10-25T14:28:00Z", "The 'exfil_timestamp' value is incorrect."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
