#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import re
import math
import pytest

def is_malformed(text):
    idx = text.find('\\u')
    while idx != -1:
        if idx + 6 > len(text):
            return True
        hex_part = text[idx+2:idx+6]
        if not re.match(r'^[0-9a-fA-F]{4}$', hex_part):
            return True
        idx = text.find('\\u', idx + 1)
    return False

def compute_expected_stats():
    input_file = '/home/user/raw_logs.csv'
    assert os.path.isfile(input_file), f"Input file {input_file} is missing."

    buckets = {}

    with open(input_file, 'r', newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts = int(row['timestamp_sec'])
            text = row['query_text']

            bucket_ts = (ts // 300) * 300
            malformed = is_malformed(text)
            length = len(text)

            if bucket_ts not in buckets:
                buckets[bucket_ts] = {'count': 0, 'malformed_count': 0, 'sum_len': 0}

            buckets[bucket_ts]['count'] += 1
            if malformed:
                buckets[bucket_ts]['malformed_count'] += 1
            buckets[bucket_ts]['sum_len'] += length

    expected_rows = []
    sorted_buckets = sorted(buckets.keys())

    for b in sorted_buckets:
        window_sum_len = buckets[b]['sum_len']
        window_count = buckets[b]['count']

        for prev_b in (b - 300, b - 600):
            if prev_b in buckets:
                window_sum_len += buckets[prev_b]['sum_len']
                window_count += buckets[prev_b]['count']

        rolling_avg = math.floor(window_sum_len / window_count)

        ratio = buckets[b]['malformed_count'] / buckets[b]['count']
        status = 'FLAGGED' if ratio > 0.05 else 'OK'

        expected_rows.append({
            'bucket_start_ts': str(b),
            'query_count': str(buckets[b]['count']),
            'rolling_avg_length': str(rolling_avg),
            'status': status
        })

    return expected_rows

def test_aggregated_stats_exists():
    output_file = '/home/user/aggregated_stats.csv'
    assert os.path.isfile(output_file), f"Output file {output_file} was not generated."

def test_aggregated_stats_content():
    output_file = '/home/user/aggregated_stats.csv'
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    expected_rows = compute_expected_stats()

    actual_rows = []
    with open(output_file, 'r', newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['bucket_start_ts', 'query_count', 'rolling_avg_length', 'status'], \
            f"Incorrect headers: {reader.fieldnames}"
        for row in reader:
            actual_rows.append(row)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, got {len(actual_rows)}"

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
