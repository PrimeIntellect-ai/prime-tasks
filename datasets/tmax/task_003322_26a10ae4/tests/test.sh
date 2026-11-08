#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import unicodedata
import re
from collections import defaultdict
import pytest

RAW_FILE = "/home/user/raw_messages.jsonl"
PROCESSED_FILE = "/home/user/processed_messages.jsonl"

def normalize_text(text):
    # Apply NFC
    text = unicodedata.normalize('NFC', text)
    # Convert to lowercase
    text = text.lower()
    # Standardize whitespace and trim
    text = re.sub(r'\s+', ' ', text).strip()
    return text

def compute_expected_output():
    if not os.path.exists(RAW_FILE):
        pytest.fail(f"Input file {RAW_FILE} is missing.")

    raw_records = []
    with open(RAW_FILE, 'r', encoding='utf-8') as f:
        for line in f:
            if line.strip():
                raw_records.append(json.loads(line))

    # Group by user_id
    groups = defaultdict(list)
    for record in raw_records:
        groups[record['user_id']].append(record)

    expected_records = []

    # Sort user_ids alphabetically
    for user_id in sorted(groups.keys()):
        # Sort chronologically (stable sort provided by Python's sorted)
        user_records = sorted(groups[user_id], key=lambda x: x['timestamp'])

        window = []
        for rec in user_records:
            norm_text = normalize_text(rec['text'])
            # Length in Unicode scalar values (Python's len() does exactly this)
            char_count = len(norm_text)
            window.append(char_count)
            if len(window) > 3:
                window.pop(0)

            rolling_avg = sum(window) / len(window)
            rolling_avg_rounded = round(rolling_avg, 2)

            expected_records.append({
                "user_id": user_id,
                "timestamp": rec['timestamp'],
                "normalized_text": norm_text,
                "rolling_avg_len": rolling_avg_rounded
            })

    return expected_records

def test_processed_file_exists():
    assert os.path.exists(PROCESSED_FILE), f"The output file {PROCESSED_FILE} is missing. Did the Rust program run successfully?"
    assert os.path.isfile(PROCESSED_FILE), f"{PROCESSED_FILE} is not a valid file."

def test_processed_file_content():
    if not os.path.exists(PROCESSED_FILE):
        pytest.fail(f"Cannot verify content because {PROCESSED_FILE} is missing.")

    expected = compute_expected_output()

    actual = []
    with open(PROCESSED_FILE, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                actual.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {PROCESSED_FILE} is not valid JSON.")

    assert len(actual) == len(expected), f"Expected {len(expected)} records in {PROCESSED_FILE}, but got {len(actual)}."

    for i, (exp, act) in enumerate(zip(expected, actual)):
        assert act.get('user_id') == exp['user_id'], f"Record {i+1}: Expected user_id '{exp['user_id']}', got '{act.get('user_id')}'."
        assert act.get('timestamp') == exp['timestamp'], f"Record {i+1}: Expected timestamp {exp['timestamp']}, got {act.get('timestamp')}."
        assert act.get('normalized_text') == exp['normalized_text'], f"Record {i+1}: Expected normalized_text '{exp['normalized_text']}', got '{act.get('normalized_text')}'."

        # Check rolling average with tolerance for floating point representation
        act_avg = act.get('rolling_avg_len')
        assert act_avg is not None, f"Record {i+1}: Missing 'rolling_avg_len'."
        assert isinstance(act_avg, (int, float)), f"Record {i+1}: 'rolling_avg_len' must be a number."
        assert abs(act_avg - exp['rolling_avg_len']) <= 0.01, f"Record {i+1}: Expected rolling_avg_len approx {exp['rolling_avg_len']}, got {act_avg}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
