#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import re
import pytest

def get_expected_data():
    log_file_path = "/home/user/app_logs.txt"
    assert os.path.exists(log_file_path), f"Input log file {log_file_path} is missing."

    pattern = re.compile(r"^\[(.*?)\] ERROR from (.*?): User '(.*?)' failed to login \(Code: (\d+)\)$")

    total_lines = 0
    valid_lines = 0
    unique_valid_lines = 0

    records = []
    seen = set()

    with open(log_file_path, "r") as f:
        for line in f:
            total_lines += 1
            line = line.strip()
            match = pattern.search(line)
            if match:
                valid_lines += 1
                timestamp, ip_address, username, error_code = match.groups()
                record = {
                    "timestamp": timestamp,
                    "ip_address": ip_address,
                    "username": username,
                    "error_code": int(error_code)
                }

                record_tuple = (timestamp, ip_address, username, int(error_code))
                if record_tuple not in seen:
                    seen.add(record_tuple)
                    records.append(record)
                    unique_valid_lines += 1

    summary = {
        "total_lines": total_lines,
        "valid_lines": valid_lines,
        "unique_valid_lines": unique_valid_lines
    }

    return records, summary

def test_clean_logs_jsonl():
    clean_logs_path = "/home/user/clean_logs.jsonl"
    assert os.path.exists(clean_logs_path), f"Output file {clean_logs_path} is missing."

    expected_records, _ = get_expected_data()

    actual_records = []
    with open(clean_logs_path, "r") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                actual_records.append(record)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {clean_logs_path} is not valid JSON.")

    assert len(actual_records) == len(expected_records), f"Expected {len(expected_records)} records in {clean_logs_path}, but found {len(actual_records)}."

    for i, (actual, expected) in enumerate(zip(actual_records, expected_records)):
        assert actual == expected, f"Record at index {i} in {clean_logs_path} does not match expected.\nExpected: {expected}\nActual: {actual}"

def test_processing_summary_json():
    summary_path = "/home/user/processing_summary.json"
    assert os.path.exists(summary_path), f"Output file {summary_path} is missing."

    _, expected_summary = get_expected_data()

    with open(summary_path, "r") as f:
        try:
            actual_summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {summary_path} is not valid JSON.")

    assert actual_summary == expected_summary, f"Summary in {summary_path} does not match expected.\nExpected: {expected_summary}\nActual: {actual_summary}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
