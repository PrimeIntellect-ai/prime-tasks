#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

REPORT_FILE = "/home/user/analysis_report.json"

def test_report_file_exists():
    assert os.path.isfile(REPORT_FILE), f"The required output file {REPORT_FILE} does not exist."

def test_report_content():
    assert os.path.isfile(REPORT_FILE), f"Cannot check content, {REPORT_FILE} is missing."

    with open(REPORT_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_FILE} does not contain valid JSON.")

    assert "target_company_id" in data, "Missing 'target_company_id' in JSON report."
    assert "target_company_name" in data, "Missing 'target_company_name' in JSON report."
    assert "incoming_supplies_count" in data, "Missing 'incoming_supplies_count' in JSON report."

    assert data["target_company_id"] == "E7", f"Expected target_company_id to be 'E7', got {data['target_company_id']}"
    assert data["target_company_name"] == "CorpGamma", f"Expected target_company_name to be 'CorpGamma', got {data['target_company_name']}"
    assert data["incoming_supplies_count"] == 3, f"Expected incoming_supplies_count to be 3, got {data['incoming_supplies_count']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
