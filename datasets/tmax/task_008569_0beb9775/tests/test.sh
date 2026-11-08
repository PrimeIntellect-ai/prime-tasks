#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

REPORT_PATH = "/home/user/policy_report.json"

def test_report_exists_and_is_valid_json():
    assert os.path.isfile(REPORT_PATH), f"The report file {REPORT_PATH} does not exist."
    try:
        with open(REPORT_PATH, "r") as f:
            json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

def test_report_content():
    assert os.path.isfile(REPORT_PATH), f"The report file {REPORT_PATH} does not exist."
    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Cannot parse JSON report.")

    # Check ssh_hardened
    assert "ssh_hardened" in data, "Key 'ssh_hardened' is missing from the report."
    assert data["ssh_hardened"] is False, "Expected 'ssh_hardened' to be false (PermitRootLogin is yes)."

    # Check cert_valid
    assert "cert_valid" in data, "Key 'cert_valid' is missing from the report."
    assert data["cert_valid"] is False, "Expected 'cert_valid' to be false (cert.pem is not signed by ca.pem)."

    # Check corrupted_files
    assert "corrupted_files" in data, "Key 'corrupted_files' is missing from the report."
    corrupted_files = data["corrupted_files"]
    assert isinstance(corrupted_files, list), "'corrupted_files' should be a list."
    assert len(corrupted_files) == 1, f"Expected exactly 1 corrupted file, found {len(corrupted_files)}."
    assert corrupted_files[0] == "utils.js", f"Expected 'utils.js' in corrupted_files, found {corrupted_files[0]}."

    # Check identified_cwes
    assert "identified_cwes" in data, "Key 'identified_cwes' is missing from the report."
    identified_cwes = data["identified_cwes"]
    assert isinstance(identified_cwes, list), "'identified_cwes' should be a list."
    assert len(identified_cwes) == 2, f"Expected exactly 2 identified CWEs, found {len(identified_cwes)}."

    expected_cwes = ["CWE-78", "CWE-798"]
    assert sorted(identified_cwes) == expected_cwes, f"Expected identified_cwes to be {expected_cwes}, but got {identified_cwes}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
