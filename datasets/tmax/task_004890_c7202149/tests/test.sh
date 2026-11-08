#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import hashlib
import pytest

PROCESSED_LOGS_PATH = "/home/user/processed_logs.csv"
HASH_MAPPING_PATH = "/home/user/hash_mapping.json"

def get_expected_mapping():
    raw_texts = [
        "Great service!",
        "Bad, bad...",
        "Okay.",
        "Could be better!!!",
        "100% awesome"
    ]

    mapping = {}
    for text in raw_texts:
        # Normalize
        normalized = "".join(c if c.isalnum() or c.isspace() else "" for c in text.lower())
        normalized = " ".join(normalized.split())

        # Hash
        md5_hash = hashlib.md5(normalized.encode('utf-8')).hexdigest()
        mapping[md5_hash] = normalized

    return mapping

def test_hash_mapping_json():
    assert os.path.exists(HASH_MAPPING_PATH), f"File not found: {HASH_MAPPING_PATH}"

    with open(HASH_MAPPING_PATH, 'r', encoding='utf-8') as f:
        try:
            actual_mapping = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {HASH_MAPPING_PATH} is not valid JSON.")

    expected_mapping = get_expected_mapping()

    assert actual_mapping == expected_mapping, (
        f"Hash mapping does not match expected.\n"
        f"Expected: {expected_mapping}\n"
        f"Actual: {actual_mapping}"
    )

def test_processed_logs_csv():
    assert os.path.exists(PROCESSED_LOGS_PATH), f"File not found: {PROCESSED_LOGS_PATH}"

    expected_mapping = get_expected_mapping()
    # Reverse mapping for easy lookup (normalized text -> hash)
    # Actually, we can just hardcode the expected rows based on the logic to ensure correctness.

    expected_rows = [
        ['u1', '2023-11-01', '21b5cf360c7f0932aabddcd7f07e5e39'],
        ['u1', '2023-11-02', ''],
        ['u1', '2023-11-03', '7027c4273f7cd9aab53c1538fc1209b5'],
        ['u1', '2023-11-04', '21b5cf360c7f0932aabddcd7f07e5e39'],
        ['u2', '2023-11-01', ''],
        ['u2', '2023-11-02', ''],
        ['u2', '2023-11-03', 'ef5ca5552ebc572b9a149c4f58f000db'],
        ['u2', '2023-11-04', ''],
        ['u3', '2023-11-01', '01a7d65691deff1f97c5efc0780f2d57'],
        ['u3', '2023-11-02', ''],
        ['u3', '2023-11-03', ''],
        ['u3', '2023-11-04', 'fdd1fb20d75062a4bdf6ed2d0cd21183']
    ]

    with open(PROCESSED_LOGS_PATH, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['user_id', 'date', 'text_hash'], f"Incorrect CSV header. Got: {header}"

        actual_rows = list(reader)

    assert actual_rows == expected_rows, (
        f"Processed logs CSV content or sorting is incorrect.\n"
        f"Expected rows: {expected_rows}\n"
        f"Actual rows: {actual_rows}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
