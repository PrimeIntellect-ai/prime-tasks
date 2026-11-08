#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_incident_report_exists():
    path = "/home/user/incident_report.json"
    assert os.path.exists(path), f"Incident report file is missing at {path}."
    assert os.path.isfile(path), f"Path {path} is not a file."

def test_incident_report_content():
    path = "/home/user/incident_report.json"
    assert os.path.exists(path), f"Incident report file is missing at {path}."

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")

    expected_encoded = "c2VjcmV0X2FkbWluX3Rva2VuXzEwMTk="
    expected_decoded = "secret_admin_token_1019"
    expected_cwe = "CWE-214"
    expected_flag = "FLAG{proc_cmdline_leak_secured}"

    assert "leaked_token_encoded" in data, "Missing 'leaked_token_encoded' in JSON."
    assert data["leaked_token_encoded"] == expected_encoded, f"Expected encoded token {expected_encoded}, got {data['leaked_token_encoded']}."

    assert "leaked_token_decoded" in data, "Missing 'leaked_token_decoded' in JSON."
    assert data["leaked_token_decoded"] == expected_decoded, f"Expected decoded token {expected_decoded}, got {data['leaked_token_decoded']}."

    assert "cwe_id" in data, "Missing 'cwe_id' in JSON."
    assert data["cwe_id"].upper() == expected_cwe, f"Expected CWE ID {expected_cwe}, got {data['cwe_id']}."

    assert "retrieved_flag" in data, "Missing 'retrieved_flag' in JSON."
    assert data["retrieved_flag"] == expected_flag, f"Expected retrieved flag {expected_flag}, got {data['retrieved_flag']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
