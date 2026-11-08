#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import math
import pytest

def get_percentile(data, p):
    data = sorted(data)
    n = len(data)
    if n == 0:
        return None
    k = (n - 1) * p
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return data[f]
    return data[f] * (c - k) + data[c] * (k - f)

def test_best_model_output():
    input_file = '/home/user/experiments.jsonl'
    output_file = '/home/user/best_model.json'

    assert os.path.isfile(input_file), f"Input file {input_file} is missing."
    assert os.path.isfile(output_file), f"Output file {output_file} was not created."

    # Process the input file to determine the expected result dynamically
    valid_records = []
    with open(input_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            record = json.loads(line)
            if record.get('latency_ms') is not None and record.get('accuracy') is not None:
                valid_records.append(record)

    assert len(valid_records) > 0, "No valid records found in the input file."

    latencies = [r['latency_ms'] for r in valid_records]
    p90 = get_percentile(latencies, 0.90)

    # Filter by outlier and accuracy
    filtered_records = [
        r for r in valid_records 
        if r['latency_ms'] <= p90 and r['accuracy'] >= 0.90
    ]

    assert len(filtered_records) > 0, "No records left after filtering for outliers and accuracy."

    # Find the best model (lowest latency)
    best_record = min(filtered_records, key=lambda x: x['latency_ms'])

    # Compute expected embedding
    config_str = best_record['config_string']
    expected_embedding = hashlib.sha256(config_str.encode('utf-8')).hexdigest()

    expected_output = {
        "model_id": best_record["model_id"],
        "embedding": expected_embedding,
        "latency_ms": best_record["latency_ms"]
    }

    # Read the actual output
    with open(output_file, 'r') as f:
        try:
            actual_output = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {output_file} does not contain valid JSON.")

    # Assert expected vs actual
    assert actual_output.get("model_id") == expected_output["model_id"], \
        f"Expected model_id {expected_output['model_id']}, got {actual_output.get('model_id')}"

    assert actual_output.get("embedding") == expected_output["embedding"], \
        f"Expected embedding {expected_output['embedding']}, got {actual_output.get('embedding')}"

    assert actual_output.get("latency_ms") == expected_output["latency_ms"], \
        f"Expected latency_ms {expected_output['latency_ms']}, got {actual_output.get('latency_ms')}"

    # Verify no extra keys are present
    assert set(actual_output.keys()) == set(expected_output.keys()), \
        f"Output JSON keys {list(actual_output.keys())} do not match expected keys {list(expected_output.keys())}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
