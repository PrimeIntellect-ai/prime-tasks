#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json

def test_output_files_exist():
    """Verify that the output files exist."""
    assert os.path.isfile("/home/user/processed_changes.jsonl"), "Output file /home/user/processed_changes.jsonl is missing."
    assert os.path.isfile("/home/user/pipeline.log"), "Output file /home/user/pipeline.log is missing."

def test_jsonl_content():
    """Verify the content of the processed JSON Lines file."""
    expected_records = [
        {
            "ticket_id": "CHG001",
            "notes": "Initial deployment of the web server configuration.",
            "timestamp": "2023-10-01T10:00:00Z",
            "target_ip": "X.X.5.22",
            "password": "[REDACTED]"
        },
        {
            "ticket_id": "CHG002",
            "notes": "Restarted service. No password changes.",
            "timestamp": "2023-10-01T10:00:00Z",
            "target_ip": "X.X.254.1"
        },
        {
            "ticket_id": "CHG003",
            "notes": "Upgraded database schema. Applied migrations.",
            "timestamp": "2023-10-02T14:30:00Z",
            "target_ip": "X.X.100.5",
            "password": "[REDACTED]"
        },
        {
            "ticket_id": "CHG004",
            "notes": "DNS update only.",
            "timestamp": "2023-10-02T14:30:00Z",
            "target_ip": "X.X.4.4"
        }
    ]

    actual_records = []
    with open("/home/user/processed_changes.jsonl", "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                actual_records.append(json.loads(line))
            except json.JSONDecodeError:
                assert False, f"Invalid JSON line found: {line}"

    assert len(actual_records) == len(expected_records), f"Expected {len(expected_records)} records, got {len(actual_records)}"

    for i, (actual, expected) in enumerate(zip(actual_records, expected_records)):
        # If password is null in actual but missing in expected, that's acceptable per spec.
        if "password" not in expected and actual.get("password") is None:
            actual.pop("password")

        assert actual == expected, f"Record {i + 1} does not match expected output.\nExpected: {expected}\nActual: {actual}"

def test_pipeline_log_content():
    """Verify the content of the pipeline log file."""
    expected_lines = [
        "Total records processed: 4",
        "Records with imputed dates: 2",
        "Records with masked passwords: 2"
    ]

    with open("/home/user/pipeline.log", "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in pipeline.log, got {len(actual_lines)}"

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Log line {i + 1} mismatch.\nExpected: {expected}\nActual: {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
