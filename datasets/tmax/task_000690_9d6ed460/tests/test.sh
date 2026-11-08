#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import stat
import pytest

REPORT_PATH = "/home/user/incident_042/report.json"
TARGET_DIR = "/home/user/legacy_app"

def get_world_writable_files(directory):
    """Helper to dynamically find world-writable files."""
    world_writable = []
    if not os.path.isdir(directory):
        return world_writable

    for root, dirs, files in os.walk(directory):
        for f in files:
            full_path = os.path.join(root, f)
            st = os.stat(full_path)
            # Check if others have write permission
            if bool(st.st_mode & stat.S_IWOTH):
                world_writable.append(full_path)
    return sorted(world_writable)

def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing. Did you create it?"

def test_report_json_format():
    assert os.path.isfile(REPORT_PATH), "Report file missing."
    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON.")

    assert "decrypted_payload" in data, f"Report {REPORT_PATH} is missing the 'decrypted_payload' key."
    assert "privesc_candidates" in data, f"Report {REPORT_PATH} is missing the 'privesc_candidates' key."

def test_report_decrypted_payload():
    assert os.path.isfile(REPORT_PATH), "Report file missing."
    with open(REPORT_PATH, 'r') as f:
        data = json.load(f)

    payload = data.get("decrypted_payload", {})
    assert isinstance(payload, dict), "'decrypted_payload' must be a JSON object (dictionary)."

    expected_cmd = "audit"
    expected_dir = "/home/user/legacy_app"
    expected_vuln = "world_writable"

    assert payload.get("cmd") == expected_cmd, f"Expected 'cmd' to be '{expected_cmd}', got '{payload.get('cmd')}'."
    assert payload.get("dir") == expected_dir, f"Expected 'dir' to be '{expected_dir}', got '{payload.get('dir')}'."
    assert payload.get("vuln") == expected_vuln, f"Expected 'vuln' to be '{expected_vuln}', got '{payload.get('vuln')}'."

def test_report_privesc_candidates():
    assert os.path.isfile(REPORT_PATH), "Report file missing."
    with open(REPORT_PATH, 'r') as f:
        data = json.load(f)

    candidates = data.get("privesc_candidates", [])
    assert isinstance(candidates, list), "'privesc_candidates' must be a JSON array (list)."

    # Dynamically compute the expected candidates based on the actual filesystem state
    expected_candidates = get_world_writable_files(TARGET_DIR)

    assert sorted(candidates) == expected_candidates, (
        f"The 'privesc_candidates' list does not match the actual world-writable files in {TARGET_DIR}.\n"
        f"Expected: {expected_candidates}\n"
        f"Got: {candidates}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
