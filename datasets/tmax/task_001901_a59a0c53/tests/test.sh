#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest
from datetime import datetime, timedelta

INPUT_FILE = "/home/user/raw_access_logs.jsonl"
OUTPUT_FILE = "/home/user/suspicious_activity.json"

def compute_expected_results(input_path):
    seen_requests = set()
    processed_logs = []

    # Read and parse logs
    with open(input_path, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            log = json.loads(line)

            # 1. Deduplication based on request_id
            req_id = log.get("request_id")
            if req_id in seen_requests:
                continue
            seen_requests.add(req_id)

            # 2. Filtering: endpoint == "/login" and status_code == 401
            if log.get("endpoint") == "/login" and log.get("status_code") == 401:
                processed_logs.append(log)

    # 3 & 4. Time-Based Bucketing and Grouping
    buckets = {}
    for log in processed_logs:
        ts_str = log.get("timestamp")
        # Parse timestamp (assuming ISO8601 format like "2023-10-01T10:03:15Z")
        ts = datetime.strptime(ts_str, "%Y-%m-%dT%H:%M:%SZ")

        # Calculate 5-minute tumbling window
        minute_bucket = (ts.minute // 5) * 5
        bucket_ts = ts.replace(minute=minute_bucket, second=0, microsecond=0)
        bucket_str = bucket_ts.strftime("%Y-%m-%dT%H:%M:%SZ")

        ip = log.get("ip_address")
        payload = log.get("payload_hash")

        key = (bucket_str, ip)
        if key not in buckets:
            buckets[key] = set()
        buckets[key].add(payload)

    # 5. Threshold filtering
    suspicious = []
    for (bucket_str, ip), payloads in buckets.items():
        if len(payloads) > 5:
            suspicious.append({
                "time_bucket": bucket_str,
                "ip_address": ip,
                "unique_payloads": len(payloads)
            })

    # 6. Sorting
    suspicious.sort(key=lambda x: (x["time_bucket"], x["ip_address"]))
    return suspicious

def test_output_file_exists():
    """Verify that the expected output file has been created."""
    assert os.path.exists(OUTPUT_FILE), f"The output file is missing: {OUTPUT_FILE}"
    assert os.path.isfile(OUTPUT_FILE), f"The path exists but is not a regular file: {OUTPUT_FILE}"

def test_output_file_format_and_correctness():
    """Verify that the output file contains the correct JSON structure and data."""
    assert os.path.exists(INPUT_FILE), f"Input file missing, cannot verify correctness: {INPUT_FILE}"

    expected_data = compute_expected_results(INPUT_FILE)

    with open(OUTPUT_FILE, 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The output file {OUTPUT_FILE} is not valid JSON.")

    assert isinstance(actual_data, list), "The output must be a JSON array (list)."

    # Check exact match
    assert actual_data == expected_data, (
        f"The output data does not match the expected results.\n"
        f"Expected: {expected_data}\n"
        f"Actual: {actual_data}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
