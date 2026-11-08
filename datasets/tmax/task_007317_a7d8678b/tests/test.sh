#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import hashlib
import pytest
from datetime import datetime

def get_expected_data(input_file):
    with open(input_file, "r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    # Sort by timestamp to ensure chronological order
    rows.sort(key=lambda x: x["timestamp"])

    severity_map = {
        "DEBUG": 1,
        "INFO": 2,
        "WARN": 3,
        "ERROR": 4,
        "FATAL": 5
    }

    seen_hashes = set()
    deduped_rows = []

    for row in rows:
        log_level = row["log_level"]
        if log_level not in severity_map:
            continue

        severity = severity_map[log_level]
        server_id = row["server_id"]
        message = row["message"]

        concat_str = f"{server_id}{log_level}{message}"
        msg_hash = hashlib.md5(concat_str.encode("utf-8")).hexdigest()

        if msg_hash not in seen_hashes:
            seen_hashes.add(msg_hash)

            # Extract hour
            dt = datetime.strptime(row["timestamp"], "%Y-%m-%dT%H:%M:%SZ")
            hour = str(dt.hour)

            deduped_rows.append({
                "timestamp": row["timestamp"],
                "server_id": server_id,
                "severity": str(severity),
                "message_hash": msg_hash,
                "hour": hour
            })

    # Stratified sampling
    grouped = {}
    sampled_rows = []

    for row in deduped_rows:
        key = (row["hour"], row["severity"])
        if key not in grouped:
            grouped[key] = 0

        if grouped[key] < 2:
            grouped[key] += 1
            sampled_rows.append(row)

    # Output columns: timestamp,server_id,severity,message_hash,hour
    expected_output = []
    for row in sampled_rows:
        expected_output.append([
            row["timestamp"],
            row["server_id"],
            row["severity"],
            row["message_hash"],
            row["hour"]
        ])

    # Sort final by timestamp ascending
    expected_output.sort(key=lambda x: x[0])
    return expected_output

def test_processed_logs_exists():
    assert os.path.isfile("/home/user/processed_logs.csv"), "The output file /home/user/processed_logs.csv does not exist."

def test_processed_logs_headers():
    with open("/home/user/processed_logs.csv", "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail("The processed_logs.csv file is empty.")

    expected_headers = ["timestamp", "server_id", "severity", "message_hash", "hour"]
    assert headers == expected_headers, f"Expected headers {expected_headers}, but got {headers}."

def test_processed_logs_data():
    input_file = "/home/user/app_logs.csv"
    output_file = "/home/user/processed_logs.csv"

    assert os.path.isfile(input_file), f"Input file {input_file} is missing."
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    expected_data = get_expected_data(input_file)

    with open(output_file, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        headers = next(reader, None)
        actual_data = list(reader)

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} rows of data, but got {len(actual_data)}."

    for i, (actual_row, expected_row) in enumerate(zip(actual_data, expected_data)):
        assert actual_row == expected_row, f"Row {i+1} mismatch.\nExpected: {expected_row}\nActual: {actual_row}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
