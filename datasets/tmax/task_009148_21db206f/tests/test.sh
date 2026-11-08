#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_processed_translations_file_exists():
    file_path = "/home/user/processed_translations.jsonl"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

def test_processed_translations_content():
    file_path = "/home/user/processed_translations.jsonl"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

    expected = [
        {
            "timestamp_utc": "2023-10-25T12:00:00Z",
            "source": "server_us.csv",
            "clean_text": "Please send the info to [EMAIL] quickly.",
            "best_match_id": "ref3",
            "similarity_score": 1.0
        },
        {
            "timestamp_utc": "2023-10-25T12:30:00Z",
            "source": "server_eu.jsonl",
            "clean_text": "Contact me at [EMAIL] for the file.",
            "best_match_id": "ref1",
            "similarity_score": 1.0
        },
        {
            "timestamp_utc": "2023-10-25T14:45:00Z",
            "source": "server_eu.jsonl",
            "clean_text": "The quick brown fox jumps over [IP].",
            "best_match_id": "ref2",
            "similarity_score": 1.0
        },
        {
            "timestamp_utc": "2023-10-25T17:00:00Z",
            "source": "server_us.csv",
            "clean_text": "The swift brown fox leaps.",
            "best_match_id": "ref4",
            "similarity_score": 1.0
        }
    ]

    with open(file_path, "r") as f:
        lines = f.read().strip().split("\n")

    # Filter out empty lines just in case
    lines = [line for line in lines if line.strip()]

    assert len(lines) == 4, f"Expected exactly 4 lines in {file_path}, but found {len(lines)}."

    for i, line in enumerate(lines):
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} is not valid JSON: {line}")

        expected_row = expected[i]

        # Check all required keys
        missing_keys = set(expected_row.keys()) - set(data.keys())
        assert not missing_keys, f"Line {i+1} is missing required keys: {missing_keys}"

        # Check values
        assert data["timestamp_utc"] == expected_row["timestamp_utc"], f"Line {i+1}: expected timestamp {expected_row['timestamp_utc']}, got {data['timestamp_utc']}"
        assert data["source"] == expected_row["source"], f"Line {i+1}: expected source {expected_row['source']}, got {data['source']}"
        assert data["clean_text"] == expected_row["clean_text"], f"Line {i+1}: expected clean_text '{expected_row['clean_text']}', got '{data['clean_text']}'"
        assert data["best_match_id"] == expected_row["best_match_id"], f"Line {i+1}: expected best_match_id '{expected_row['best_match_id']}', got '{data['best_match_id']}'"

        # Check similarity score rounded to 4 decimal places
        sim_score = round(float(data["similarity_score"]), 4)
        assert sim_score == expected_row["similarity_score"], f"Line {i+1}: expected similarity_score {expected_row['similarity_score']}, got {sim_score}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
