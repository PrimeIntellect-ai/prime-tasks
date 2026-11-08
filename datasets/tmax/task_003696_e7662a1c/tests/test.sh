#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

REPORT_PATH = "/home/user/audit_report.json"

def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"The expected report file {REPORT_PATH} does not exist."

def test_report_content():
    with open(REPORT_PATH, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} is not valid JSON.")

    assert "corrupted_archives" in data, "The key 'corrupted_archives' is missing from the JSON report."
    assert "stale_logs" in data, "The key 'stale_logs' is missing from the JSON report."

    expected_corrupted = [
        "/home/user/legacy_project/backup/archives/broken_backup.zip",
        "/home/user/legacy_project/data/corrupted_data.tar.gz"
    ]

    expected_stale = [
        "/home/user/legacy_project/data/legacy.log",
        "/home/user/legacy_project/src/logs/old_app.log"
    ]

    # Check that lists are sorted as required
    assert data["corrupted_archives"] == sorted(data["corrupted_archives"]), "The 'corrupted_archives' list is not sorted alphabetically."
    assert data["stale_logs"] == sorted(data["stale_logs"]), "The 'stale_logs' list is not sorted alphabetically."

    # Check contents
    assert data["corrupted_archives"] == expected_corrupted, f"Expected corrupted_archives to be {expected_corrupted}, got {data['corrupted_archives']}"
    assert data["stale_logs"] == expected_stale, f"Expected stale_logs to be {expected_stale}, got {data['stale_logs']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
