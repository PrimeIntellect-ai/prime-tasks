#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

EXPECTED_CSV = """ID,Name,Email,SSN,Notes
1,Alice Smith,alice@example.com,123-45-6789,Healthy patient
2,Bob Jones,bob@work.org,987-65-4321,Patient has a
bad cough
3,Charlie Brown,chuck@peanuts.com,555-66-7777,Routine checkup
4,Diana Prince,diana@amazon.com,111-22-3333,
5,Eve Hacker,eve@malicious.net,999-00-1111,Requires followup
6,Frank,frank@broken.com,222-33-4444,Missing
data
7,Grace Hopper,grace@navy.mil,888-77-6666,Excellent health
"""

def test_report_json_exists():
    """Test that the report.json file was created."""
    assert os.path.isfile("/home/user/report.json"), "The file /home/user/report.json does not exist."

def test_report_json_valid_and_correct():
    """Test that report.json is valid JSON and contains the correct transformed data."""
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), "The file /home/user/report.json does not exist."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"/home/user/report.json is not valid JSON: {e}")

    assert "dataset" in data, "Missing 'dataset' key in JSON."
    assert data["dataset"] == "patients", "The 'dataset' key should be 'patients'."

    assert "valid_count" in data, "Missing 'valid_count' key in JSON."
    assert "data" in data, "Missing 'data' key in JSON."
    assert isinstance(data["data"], list), "The 'data' key should be a list."

    # Compute expected data from the original CSV logic
    csv_path = "/home/user/patients.csv"
    assert os.path.isfile(csv_path), f"Original file {csv_path} is missing."

    with open(csv_path, "r") as f:
        csv_contents = f.read()
    assert csv_contents == EXPECTED_CSV, "The original patients.csv fixture was modified."

    expected_data = []
    lines = csv_contents.splitlines(keepends=True)

    # Skip header
    for line in lines[1:]:
        line = line.strip('\n')
        # Check if exactly 4 commas
        if line.count(',') == 4:
            parts = line.split(',')
            record_id = parts[0]
            email = parts[2]
            ssn = parts[3]

            # Extract domain
            domain = email.split('@')[-1] if '@' in email else email

            # Mask SSN
            if len(ssn) >= 4:
                masked_ssn = "XXX-XX-" + ssn[-4:]
            else:
                masked_ssn = ssn # fallback

            expected_data.append({
                "id": record_id,
                "domain": domain,
                "ssn": masked_ssn
            })

    assert data["valid_count"] == len(expected_data), f"Expected valid_count to be {len(expected_data)}, got {data['valid_count']}."

    # Compare the data array
    assert len(data["data"]) == len(expected_data), f"Expected {len(expected_data)} records in 'data', got {len(data['data'])}."

    for i, (actual, expected) in enumerate(zip(data["data"], expected_data)):
        assert actual.get("id") == expected["id"], f"Record {i}: Expected id '{expected['id']}', got '{actual.get('id')}'"
        assert actual.get("domain") == expected["domain"], f"Record {i}: Expected domain '{expected['domain']}', got '{actual.get('domain')}'"
        assert actual.get("ssn") == expected["ssn"], f"Record {i}: Expected ssn '{expected['ssn']}', got '{actual.get('ssn')}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
