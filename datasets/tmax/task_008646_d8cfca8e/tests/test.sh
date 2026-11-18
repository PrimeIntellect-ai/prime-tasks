#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_debug_report_exists():
    file_path = "/home/user/debug_report.json"
    assert os.path.isfile(file_path), f"Report file {file_path} is missing."

def test_debug_report_content():
    file_path = "/home/user/debug_report.json"
    assert os.path.isfile(file_path), f"Report file {file_path} is missing."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    assert "anomalous_ip" in data, "Key 'anomalous_ip' is missing from the JSON report."
    assert data["anomalous_ip"] == "10.0.45.22", f"Expected anomalous_ip to be '10.0.45.22', got {data['anomalous_ip']}."

    assert "anomalous_request_count" in data, "Key 'anomalous_request_count' is missing from the JSON report."
    assert data["anomalous_request_count"] == 142, f"Expected anomalous_request_count to be 142, got {data['anomalous_request_count']}."

    assert "crashing_function" in data, "Key 'crashing_function' is missing from the JSON report."
    assert data["crashing_function"] == "parse_multipart_form_data", f"Expected crashing_function to be 'parse_multipart_form_data', got {data['crashing_function']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
