#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
from collections import defaultdict

def test_report_csv_exists():
    """Verify that the report.csv file was created."""
    assert os.path.isfile("/home/user/report.csv"), "The file /home/user/report.csv does not exist."

def test_report_csv_contents():
    """Verify that the report.csv contains the correct aggregated data."""
    log_file_path = "/home/user/data/logs.jsonl"
    report_file_path = "/home/user/report.csv"

    assert os.path.isfile(log_file_path), f"Source log file {log_file_path} is missing."

    # 1. Compute expected results from the source file
    buckets = defaultdict(lambda: {"total_events": 0, "error_count": 0})

    with open(log_file_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            # 1. Filter Invalid Data
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue

            # 2. Constraint Validation
            if event.get("event_type") != "api_call":
                continue

            try:
                status_code = int(event.get("status_code", 0))
            except ValueError:
                continue

            if not (200 <= status_code <= 599):
                continue

            # 3. Time-based Bucketing
            timestamp = event.get("timestamp", "")
            if len(timestamp) < 13:
                continue

            # Extract YYYY-MM-DDTHH
            hour_bucket = timestamp[:13]

            # 4. Aggregation
            buckets[hour_bucket]["total_events"] += 1
            if status_code >= 400:
                buckets[hour_bucket]["error_count"] += 1

    expected_rows = []
    for hour in sorted(buckets.keys()):
        expected_rows.append({
            "hour": hour,
            "total_events": str(buckets[hour]["total_events"]),
            "error_count": str(buckets[hour]["error_count"])
        })

    # 2. Read actual results
    actual_rows = []
    with open(report_file_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)

        # Verify headers
        expected_fieldnames = ["hour", "total_events", "error_count"]
        assert reader.fieldnames == expected_fieldnames, \
            f"CSV header mismatch. Expected {expected_fieldnames}, got {reader.fieldnames}"

        for row in reader:
            actual_rows.append(row)

    # 3. Compare
    assert len(actual_rows) == len(expected_rows), \
        f"Row count mismatch. Expected {len(expected_rows)} rows, got {len(actual_rows)} rows."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, \
            f"Row {i+1} mismatch. Expected {expected}, got {actual}. Ensure data is sorted chronologically."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
