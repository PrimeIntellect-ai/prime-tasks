#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_fatal_alerts_jsonl_exists():
    """Check if the final output file exists."""
    file_path = "/home/user/fatal_alerts.jsonl"
    assert os.path.exists(file_path), f"The file {file_path} does not exist."
    assert os.path.isfile(file_path), f"{file_path} is not a valid file."

def test_fatal_alerts_content():
    """Verify the contents of the fatal_alerts.jsonl file."""
    expected_entries = [
        {"timestamp": "2023-10-01T10:05:00", "service": "app1", "message": "Memory corruption detected"},
        {"timestamp": "2023-10-01T10:15:00", "service": "cron", "message": "Disk full"}
    ]

    actual_entries = []
    file_path = "/home/user/fatal_alerts.jsonl"

    with open(file_path, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    parsed = json.loads(line)
                    actual_entries.append(parsed)
                except json.JSONDecodeError:
                    pytest.fail(f"Invalid JSON found in {file_path}: {line}")

    assert len(actual_entries) == len(expected_entries), \
        f"Expected {len(expected_entries)} entries, found {len(actual_entries)}."

    for expected in expected_entries:
        assert expected in actual_entries, f"Missing expected entry in {file_path}: {expected}"

    for actual in actual_entries:
        assert actual in expected_entries, f"Unexpected entry found in {file_path}: {actual}"

def test_mount_point_unmounted():
    """Ensure the mount point was gracefully unmounted."""
    mnt_path = "/home/user/mnt"
    if os.path.exists(mnt_path):
        assert not os.path.ismount(mnt_path), f"The directory {mnt_path} is still mounted. It must be unmounted."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
