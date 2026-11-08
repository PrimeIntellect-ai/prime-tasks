#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import datetime
from collections import defaultdict

def test_source_file_exists():
    """Verify that the student's C++ source file exists."""
    assert os.path.exists("/home/user/process_logs.cpp"), "Source file /home/user/process_logs.cpp is missing."

def test_anonymized_jsonl():
    """Verify that anonymized.jsonl contains the correct data."""
    input_file = "/home/user/events.jsonl"
    output_file = "/home/user/anonymized.jsonl"

    assert os.path.exists(output_file), f"Output file {output_file} is missing."

    with open(input_file, 'r') as f_in, open(output_file, 'r') as f_out:
        in_lines = f_in.read().strip().split('\n')
        out_lines = f_out.read().strip().split('\n')

    assert len(in_lines) == len(out_lines), f"Expected {len(in_lines)} lines in {output_file}, but found {len(out_lines)}."

    for i, (in_line, out_line) in enumerate(zip(in_lines, out_lines)):
        try:
            in_obj = json.loads(in_line)
        except json.JSONDecodeError:
            continue

        try:
            out_obj = json.loads(out_line)
        except json.JSONDecodeError:
            assert False, f"Line {i+1} in {output_file} is not valid JSON."

        expected_obj = dict(in_obj)
        expected_obj["username"] = "***"

        assert out_obj == expected_obj, f"Line {i+1} mismatch. Expected {expected_obj}, got {out_obj}"

def test_aggregation_csv():
    """Verify that aggregation.csv contains the correct counts and is sorted properly."""
    input_file = "/home/user/events.jsonl"
    output_file = "/home/user/aggregation.csv"

    assert os.path.exists(output_file), f"Output file {output_file} is missing."

    # Compute expected aggregations
    counts = defaultdict(int)
    with open(input_file, 'r') as f_in:
        for line in f_in:
            if not line.strip():
                continue
            obj = json.loads(line)
            ts_str = obj.get("timestamp")
            action = obj.get("action")

            # Parse timestamp to compute bucket
            dt = datetime.datetime.strptime(ts_str, "%Y-%m-%dT%H:%M:%SZ")
            dt = dt.replace(tzinfo=datetime.timezone.utc)
            epoch = int(dt.timestamp())
            bucket = epoch - (epoch % 3600)

            counts[(bucket, action)] += 1

    expected_rows = sorted([{"bucket_epoch": str(b), "action": a, "count": str(c)} for (b, a), c in counts.items()], key=lambda x: (int(x["bucket_epoch"]), x["action"]))

    # Read actual aggregations
    actual_rows = []
    with open(output_file, 'r', newline='') as f_out:
        reader = csv.DictReader(f_out)
        assert reader.fieldnames == ["bucket_epoch", "action", "count"], f"CSV headers are incorrect. Expected ['bucket_epoch', 'action', 'count'], got {reader.fieldnames}"
        for row in reader:
            actual_rows.append(row)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in CSV, but found {len(actual_rows)}."

    for i, (expected, actual) in enumerate(zip(expected_rows, actual_rows)):
        assert actual == expected, f"Row {i+1} mismatch in CSV. Expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
