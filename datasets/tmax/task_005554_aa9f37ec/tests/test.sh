#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import hashlib
from difflib import SequenceMatcher
import pytest

def test_processed_logs_json_correctness():
    """Verify that the processed_logs.json file contains the correct deduplicated and similarity-scored data."""
    input_file = '/home/user/sensor_logs.csv'
    output_file = '/home/user/processed_logs.json'

    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    # Compute expected results from the input file
    expected_results = []
    seen_hashes = set()
    prev_msg = None

    assert os.path.isfile(input_file), f"Input file {input_file} is missing."

    with open(input_file, 'r', encoding='cp1252') as f:
        reader = csv.DictReader(f)
        for row in reader:
            original_msg = row['Message']
            log_id = int(row['LogID'])

            normalized = original_msg.strip().lower()
            h = hashlib.sha256(normalized.encode('utf-8')).hexdigest()

            if h not in seen_hashes:
                seen_hashes.add(h)

                if prev_msg is None:
                    sim = 0.0
                else:
                    sim = SequenceMatcher(None, prev_msg, normalized).ratio()

                expected_results.append({
                    "LogID": log_id,
                    "Message": original_msg,
                    "Similarity": round(sim, 4)
                })
                prev_msg = normalized

    # Read the actual output
    try:
        with open(output_file, 'r', encoding='utf-8') as f:
            actual_results = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {output_file} does not contain valid JSON.")
    except Exception as e:
        pytest.fail(f"Failed to read {output_file}: {e}")

    # Compare
    assert isinstance(actual_results, list), "The output must be a JSON array."
    assert len(actual_results) == len(expected_results), f"Expected {len(expected_results)} records, got {len(actual_results)}."

    for i, (actual, expected) in enumerate(zip(actual_results, expected_results)):
        assert isinstance(actual, dict), f"Record at index {i} is not a JSON object."
        assert set(actual.keys()) == {"LogID", "Message", "Similarity"}, f"Record at index {i} has incorrect keys."

        assert actual["LogID"] == expected["LogID"], f"Record at index {i}: expected LogID {expected['LogID']}, got {actual['LogID']}."
        assert actual["Message"] == expected["Message"], f"Record at index {i}: expected Message {repr(expected['Message'])}, got {repr(actual['Message'])}."
        assert actual["Similarity"] == expected["Similarity"], f"Record at index {i}: expected Similarity {expected['Similarity']}, got {actual['Similarity']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
