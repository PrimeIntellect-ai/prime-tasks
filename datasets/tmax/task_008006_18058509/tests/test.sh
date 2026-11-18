#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import string
import csv
from collections import defaultdict

def test_cleaned_queries_output():
    input_file = "/home/user/queries.txt"
    output_file = "/home/user/cleaned_queries.csv"

    assert os.path.exists(output_file), f"Output file {output_file} does not exist."
    assert os.path.isfile(output_file), f"{output_file} is not a valid file."

    # Recompute the expected output from the input file
    assert os.path.exists(input_file), f"Input file {input_file} is missing."

    records = []
    with open(input_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip('\n')
            if not line:
                continue
            parts = line.split('|')
            if len(parts) != 3:
                continue
            timestamp, user_id, query = parts

            # Normalize query
            # 1. Convert ASCII uppercase to lowercase
            # 2. Remove ASCII punctuation
            normalized_chars = []
            for char in query:
                if ord(char) < 128:
                    if char in string.punctuation:
                        continue
                    if 'A' <= char <= 'Z':
                        normalized_chars.append(char.lower())
                    else:
                        normalized_chars.append(char)
                else:
                    normalized_chars.append(char)
            normalized_query = "".join(normalized_chars)

            records.append((user_id, timestamp, normalized_query))

    # Deduplicate: group by UserID, keep earliest timestamp for same normalized query
    grouped = defaultdict(dict)
    for user_id, timestamp, norm_query in records:
        if norm_query not in grouped[user_id]:
            grouped[user_id][norm_query] = timestamp
        else:
            if timestamp < grouped[user_id][norm_query]:
                grouped[user_id][norm_query] = timestamp

    # Flatten and sort
    final_records = []
    for user_id, queries in grouped.items():
        for norm_query, timestamp in queries.items():
            final_records.append((user_id, timestamp, norm_query))

    # Sort by UserID ascending, then Timestamp ascending
    final_records.sort(key=lambda x: (x[0], x[1]))

    expected_lines = [f"{u},{t},{q}\n" for u, t, q in final_records]

    # Read actual output
    with open(output_file, "r", encoding="utf-8") as f:
        actual_lines = f.readlines()

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in output, but found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch.\nExpected: {expected.strip()}\nActual: {actual.strip()}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
