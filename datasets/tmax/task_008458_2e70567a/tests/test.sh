#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json

def test_incident_report_exists_and_valid():
    report_path = "/home/user/incident_report.json"
    assert os.path.isfile(report_path), f"The report file {report_path} does not exist."

    with open(report_path, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {report_path} is not valid JSON."

    expected_data = {
        "attacker_ip": "10.10.50.8",
        "cwe_number": "CWE-78",
        "c2_server": "198.51.100.77",
        "elf_class": "ELF64"
    }

    for key, expected_value in expected_data.items():
        assert key in report_data, f"Missing key '{key}' in incident report."
        assert report_data[key] == expected_value, f"Incorrect value for '{key}'. Expected '{expected_value}', got '{report_data[key]}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
