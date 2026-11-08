#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

OUTPUT_FILE = "/home/user/cleaned_data.jsonl"

def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"The output file {OUTPUT_FILE} does not exist. Ensure the script created it."

def read_jsonl(filepath):
    data = []
    with open(filepath, "r") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                data.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {filepath} is not valid JSON.")
    return data

def test_output_format_and_keys():
    data = read_jsonl(OUTPUT_FILE)
    assert len(data) > 0, "The output file is empty."

    expected_keys = {"sensor_id", "timestamp", "temperature", "humidity", "heat_index"}
    for idx, record in enumerate(data):
        assert isinstance(record, dict), f"Record {idx} is not a JSON object."
        assert set(record.keys()) == expected_keys, f"Record {idx} has incorrect keys. Expected {expected_keys}, got {set(record.keys())}."

def test_timestamp_format():
    data = read_jsonl(OUTPUT_FILE)
    for idx, record in enumerate(data):
        ts = record["timestamp"]
        assert ts.endswith("Z"), f"Timestamp '{ts}' in record {idx} does not end with 'Z'."
        assert "T" in ts, f"Timestamp '{ts}' in record {idx} does not contain 'T' separator."
        # Basic length check for ISO 8601 YYYY-MM-DDTHH:MM:SSZ
        assert len(ts) == 20, f"Timestamp '{ts}' in record {idx} is not the correct length for format 'YYYY-MM-DDTHH:MM:SSZ'."

def test_heat_index_calculation():
    data = read_jsonl(OUTPUT_FILE)
    for idx, record in enumerate(data):
        temp = record["temperature"]
        hum = record["humidity"]
        expected_heat_index = round(temp + (0.5 * hum), 2)
        actual_heat_index = record["heat_index"]
        assert actual_heat_index == expected_heat_index, f"Record {idx} has incorrect heat_index. Expected {expected_heat_index}, got {actual_heat_index}."

def test_deduplication_and_sorting():
    data = read_jsonl(OUTPUT_FILE)

    # Check deduplication
    seen = set()
    for idx, record in enumerate(data):
        # Create a tuple of the identifying fields
        record_tuple = (record["sensor_id"], record["timestamp"], record["temperature"], record["humidity"])
        assert record_tuple not in seen, f"Duplicate record found at index {idx}: {record_tuple}"
        seen.add(record_tuple)

    # Check sorting
    for i in range(len(data) - 1):
        current_record = data[i]
        next_record = data[i+1]

        # Sort by sensor_id, then timestamp
        current_key = (current_record["sensor_id"], current_record["timestamp"])
        next_key = (next_record["sensor_id"], next_record["timestamp"])

        assert current_key <= next_key, f"Records are not sorted correctly. Record at index {i} ({current_key}) comes after record at index {i+1} ({next_key})."

def test_exact_expected_data():
    data = read_jsonl(OUTPUT_FILE)

    expected = [
        {"sensor_id": "A1", "timestamp": "2023-10-01T12:00:00Z", "temperature": 25.5, "humidity": 60, "heat_index": 55.5},
        {"sensor_id": "A1", "timestamp": "2023-10-01T12:05:00Z", "temperature": 26.0, "humidity": 62, "heat_index": 57.0},
        {"sensor_id": "B2", "timestamp": "2023-10-01T12:00:00Z", "temperature": 22.1, "humidity": 50, "heat_index": 47.1},
        {"sensor_id": "B2", "timestamp": "2023-10-01T12:05:00Z", "temperature": 22.5, "humidity": 52, "heat_index": 48.5},
        {"sensor_id": "C3", "timestamp": "2023-10-01T12:10:00Z", "temperature": 28.0, "humidity": 70, "heat_index": 63.0}
    ]

    assert len(data) == len(expected), f"Expected {len(expected)} records, but got {len(data)}."

    for i, (actual_rec, expected_rec) in enumerate(zip(data, expected)):
        assert actual_rec == expected_rec, f"Record at index {i} does not match expected.\nActual: {actual_rec}\nExpected: {expected_rec}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
