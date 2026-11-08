#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_clean_transcripts_exists():
    clean_jsonl_path = "/home/user/clean_transcripts.jsonl"
    assert os.path.exists(clean_jsonl_path), f"The output file {clean_jsonl_path} is missing."
    assert os.path.isfile(clean_jsonl_path), f"The path {clean_jsonl_path} is not a file."

def test_clean_transcripts_content():
    clean_jsonl_path = "/home/user/clean_transcripts.jsonl"

    expected_data = [
        {
            "transcript_id": "T001",
            "date": "2022-12-31",
            "customer_email": "[REDACTED_EMAIL]",
            "cc_number": "XXXX-XXXX-XXXX-3456",
            "transcript_text": "hello i need help with my account. email me at [REDACTED_EMAIL]!"
        },
        {
            "transcript_id": "T002",
            "date": "2023-01-15",
            "customer_email": "[REDACTED_EMAIL]",
            "cc_number": "XXXX-XXXX-XXXX-7654",
            "transcript_text": "my card was charged twice."
        },
        {
            "transcript_id": "T003",
            "date": "2023-02-15",
            "customer_email": "[REDACTED_EMAIL]",
            "cc_number": "XXXX-XXXX-XXXX-4444",
            "transcript_text": "update my billing to [REDACTED_EMAIL] please. thanks."
        },
        {
            "transcript_id": "T004",
            "date": "2023-03-05",
            "customer_email": "[REDACTED_EMAIL]",
            "cc_number": "XXXX-XXXX-XXXX-7777",
            "transcript_text": "cancel my subscription."
        }
    ]

    actual_data = []
    with open(clean_jsonl_path, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                actual_data.append(obj)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {clean_jsonl_path} is not valid JSON.")

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} records, but found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, f"Record {i+1} does not match expected output.\nActual: {actual}\nExpected: {expected}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
