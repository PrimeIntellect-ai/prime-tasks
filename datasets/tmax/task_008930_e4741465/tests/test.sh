#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
from datetime import datetime, timezone
import pytest

def levenshtein(s1: str, s2: str) -> int:
    if len(s1) < len(s2):
        return levenshtein(s2, s1)
    if len(s2) == 0:
        return len(s1)
    previous_row = list(range(len(s2) + 1))
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    return previous_row[-1]

def test_analyze_go_exists():
    """Check that the Go source file was created."""
    assert os.path.isfile("/home/user/analyze.go"), "The file /home/user/analyze.go does not exist."

def test_output_csv_correctness():
    """Derive the expected output from the input CSV and compare it with the actual output."""
    input_path = "/home/user/data/config_commits.csv"
    output_path = "/home/user/output.csv"

    assert os.path.isfile(input_path), f"Input file {input_path} is missing."
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

    # Compute expected results
    results = {}
    with open(input_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            ts, config_key, val_en, val_ru, val_ja = row

            # Convert timestamp to UTC hourly bucket
            dt = datetime.fromtimestamp(int(ts), tz=timezone.utc)
            bucket = dt.strftime("%Y-%m-%dT%H")

            # Calculate distances
            dist_ru = levenshtein(val_en, val_ru)
            dist_ja = levenshtein(val_en, val_ja)

            # Update max distances
            key_ru = (bucket, config_key, "en-ru")
            key_ja = (bucket, config_key, "en-ja")

            results[key_ru] = max(results.get(key_ru, -1), dist_ru)
            results[key_ja] = max(results.get(key_ja, -1), dist_ja)

    expected_rows = []
    for (bucket, config_key, lang_pair), max_dist in results.items():
        expected_rows.append([bucket, config_key, lang_pair, str(max_dist)])

    # Sort as required: bucket (asc), config_key (asc), lang_pair (asc)
    expected_rows.sort(key=lambda x: (x[0], x[1], x[2]))

    # Read actual output
    actual_rows = []
    with open(output_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["bucket", "config_key", "lang_pair", "max_distance"], \
            f"Output CSV header is incorrect. Got: {header}"
        for row in reader:
            if row:
                actual_rows.append(row)

    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} data rows, but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, \
            f"Row {i+1} mismatch. Expected {expected}, but got {actual}. Check distance calculation and sorting."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
