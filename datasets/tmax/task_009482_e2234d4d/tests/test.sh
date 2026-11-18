#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

OUTPUT_DIR = '/home/user/output'
OUTPUT_FILE = '/home/user/output/clean_logs.jsonl'

def test_output_directory_exists():
    assert os.path.isdir(OUTPUT_DIR), f"The directory {OUTPUT_DIR} does not exist."

def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"The file {OUTPUT_FILE} does not exist."

def test_output_file_content_and_format():
    assert os.path.isfile(OUTPUT_FILE), f"The file {OUTPUT_FILE} does not exist."

    records = []
    with open(OUTPUT_FILE, 'r') as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                records.append(record)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {OUTPUT_FILE} is not valid JSON: {line}")

    assert len(records) == 4, f"Expected exactly 4 deduplicated records, but found {len(records)}."

    # Check if records have the correct keys
    expected_keys = {"id", "timestamp", "log_message"}
    for idx, record in enumerate(records):
        assert set(record.keys()) == expected_keys, f"Record at index {idx} does not have the exact keys: {expected_keys}"

    # Check sorted order by id
    ids = [record['id'] for record in records]
    assert ids == sorted(ids), f"Records are not sorted by id in ascending order. Found ids: {ids}"

    # Check exact expected records based on deduplication logic
    expected_ids = [1, 3, 5, 7]
    assert ids == expected_ids, f"Expected records with IDs {expected_ids}, but found {ids}. Deduplication logic might be incorrect."

    # Verify the exact content of the records
    expected_records = {
        1: {"id": 1, "timestamp": 1620000000, "log_message": "Connection timeout on database port 5432."},
        3: {"id": 3, "timestamp": 1620000050, "log_message": "Successful extraction of 500 rows."},
        5: {"id": 5, "timestamp": 1620000100, "log_message": "Memory limit exceeded during aggregation phase."},
        7: {"id": 7, "timestamp": 1620000200, "log_message": "Pipeline finished successfully with 0 errors."}
    }

    for record in records:
        rec_id = record['id']
        expected = expected_records[rec_id]
        assert record['timestamp'] == expected['timestamp'], f"Timestamp mismatch for ID {rec_id}. Expected {expected['timestamp']}, got {record['timestamp']}"
        assert record['log_message'] == expected['log_message'], f"Log message mismatch for ID {rec_id}. Expected '{expected['log_message']}', got '{record['log_message']}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
