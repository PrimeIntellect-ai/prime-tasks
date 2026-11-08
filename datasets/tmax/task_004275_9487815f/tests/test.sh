#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def get_expected_records():
    """Derive the expected records dynamically from the source data."""
    source_file = "/home/user/data/translations.jsonl"
    assert os.path.exists(source_file), f"Source file {source_file} is missing."

    expected = []
    window = []
    with open(source_file, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            record = json.loads(line)
            ratio = len(record['es']) / len(record['en'])
            window.append(ratio)
            if len(window) > 10:
                window.pop(0)

            avg = sum(window) / len(window)
            if avg > 2.0:
                expected.append(record)
                if len(expected) == 5:
                    break
    return expected

def test_flagged_json_file():
    flagged_path = "/home/user/flagged.json"
    assert os.path.exists(flagged_path), f"Expected output file {flagged_path} is missing."

    with open(flagged_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {flagged_path} does not contain valid JSON.")

    assert isinstance(data, list), f"Expected a JSON array in {flagged_path}, but got {type(data).__name__}."

    expected_records = get_expected_records()
    expected_ids = [r['id'] for r in expected_records]
    actual_ids = [r.get('id') for r in data if isinstance(r, dict)]

    assert actual_ids == expected_ids, f"Expected IDs {expected_ids} in {flagged_path}, but got {actual_ids}."
    assert data == expected_records, f"The records in {flagged_path} do not exactly match the expected records."

def test_server_received_json():
    received_path = "/home/user/server/received.json"
    assert os.path.exists(received_path), f"The QA server did not receive the file or failed to save it to {received_path}."

    with open(received_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {received_path} does not contain valid JSON.")

    assert isinstance(data, list), f"Expected a JSON array in {received_path}, but got {type(data).__name__}."

    expected_records = get_expected_records()
    expected_ids = [r['id'] for r in expected_records]
    actual_ids = [r.get('id') for r in data if isinstance(r, dict)]

    assert actual_ids == expected_ids, f"Expected IDs {expected_ids} in {received_path}, but got {actual_ids}."
    assert data == expected_records, f"The records in {received_path} do not exactly match the expected records."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
