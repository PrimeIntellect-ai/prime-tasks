#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

REPORT_PATH = '/home/user/report.json'

def test_report_exists():
    """Test that the final report JSON file exists."""
    assert os.path.isfile(REPORT_PATH), f"The file {REPORT_PATH} does not exist. Did you create the report?"

def test_report_contents():
    """Test that the report contains the correct forensic analysis results."""
    assert os.path.isfile(REPORT_PATH), f"The file {REPORT_PATH} does not exist."

    with open(REPORT_PATH, 'r') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

    assert isinstance(report_data, dict), f"The JSON in {REPORT_PATH} should be an object (dictionary)."

    expected_ip = "192.168.1.100"
    expected_key = "deadbeef12345678"
    expected_flag = "FLAG{3lf_x0r_f0r3ns1cs_99}"

    assert "attacker_ip" in report_data, "The key 'attacker_ip' is missing from the report."
    assert report_data["attacker_ip"] == expected_ip, f"Incorrect attacker_ip. Expected '{expected_ip}', got '{report_data['attacker_ip']}'."

    assert "extracted_key_hex" in report_data, "The key 'extracted_key_hex' is missing from the report."
    assert report_data["extracted_key_hex"].lower() == expected_key, f"Incorrect extracted_key_hex. Expected '{expected_key}', got '{report_data['extracted_key_hex']}'."

    assert "decrypted_flag" in report_data, "The key 'decrypted_flag' is missing from the report."
    assert report_data["decrypted_flag"] == expected_flag, f"Incorrect decrypted_flag. Expected '{expected_flag}', got '{report_data['decrypted_flag']}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
