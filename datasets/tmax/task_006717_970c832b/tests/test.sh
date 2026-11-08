#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import pytest
from datetime import datetime, timezone
from collections import defaultdict

HOME_DIR = "/home/user"
TM_FILE = os.path.join(HOME_DIR, "tm.csv")
ACTIVITY_FILE = os.path.join(HOME_DIR, "activity.json")
OUTPUT_FILE = os.path.join(HOME_DIR, "bucket_analysis.csv")

def levenshtein(s1, s2):
    if len(s1) < len(s2):
        return levenshtein(s2, s1)
    if len(s2) == 0:
        return len(s1)
    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    return previous_row[-1]

def parse_time_to_utc_bucket(t_str):
    if t_str.endswith('Z'):
        t_str = t_str[:-1] + '+0000'
    dt = datetime.strptime(t_str, "%Y-%m-%dT%H:%M:%S%z")
    dt_utc = dt.astimezone(timezone.utc)
    bucket = dt_utc.replace(minute=0, second=0, microsecond=0)
    return bucket.strftime("%Y-%m-%dT%H:%M:%SZ")

def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} was not created."

def test_output_file_contents():
    # 1. Read input data to compute expected output
    assert os.path.isfile(TM_FILE), f"{TM_FILE} is missing."
    assert os.path.isfile(ACTIVITY_FILE), f"{ACTIVITY_FILE} is missing."

    with open(TM_FILE, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        tm_sources = [row["source"] for row in reader]

    with open(ACTIVITY_FILE, "r", encoding="utf-8") as f:
        activities = json.load(f)

    # 2. Compute expected buckets and distances
    buckets = defaultdict(list)
    for act in activities:
        bucket_str = parse_time_to_utc_bucket(act["time"])
        min_dist = min(levenshtein(act["source"], tm_src) for tm_src in tm_sources)
        buckets[bucket_str].append(min_dist)

    expected_rows = []
    for bucket_str in sorted(buckets.keys()):
        dists = buckets[bucket_str]
        avg_dist = sum(dists) / len(dists)
        expected_rows.append({
            "bucket_utc": bucket_str,
            "avg_min_distance": f"{avg_dist:.2f}"
        })

    # 3. Read actual output
    with open(OUTPUT_FILE, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        actual_rows = list(reader)

    # 4. Compare
    assert reader.fieldnames == ["bucket_utc", "avg_min_distance"], \
        f"CSV headers are incorrect. Expected ['bucket_utc', 'avg_min_distance'], got {reader.fieldnames}"

    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows in output, got {len(actual_rows)}."

    for expected, actual in zip(expected_rows, actual_rows):
        assert actual["bucket_utc"] == expected["bucket_utc"], \
            f"Expected bucket {expected['bucket_utc']}, got {actual['bucket_utc']}."
        assert actual["avg_min_distance"] == expected["avg_min_distance"], \
            f"Expected average distance {expected['avg_min_distance']} for bucket {expected['bucket_utc']}, got {actual['avg_min_distance']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
