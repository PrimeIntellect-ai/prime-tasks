#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

INPUT_FILE = "/home/user/loc_drop/raw_telemetry.jsonl"
OUTPUT_DIR = "/home/user/loc_drop/aggregated"

def compute_expected_state():
    if not os.path.exists(INPUT_FILE):
        pytest.fail(f"Input file {INPUT_FILE} is missing.")

    expected_data = {}

    with open(INPUT_FILE, 'r', encoding='utf-8') as f:
        for line in f:
            if not line.strip():
                continue
            record = json.loads(line)

            # 1. Filter out corrupt data
            if '\ufffd' in record['text']:
                continue

            # 2. Time Bucketing
            ts = record['ts']
            date = ts[:10]
            lang = record['lang']
            str_id = record['str_id']

            # 3. Grouping & Aggregation
            key = (lang, date)
            if key not in expected_data:
                expected_data[key] = {}

            if str_id not in expected_data[key]:
                expected_data[key][str_id] = record
            else:
                existing = expected_data[key][str_id]
                # Compare score, then timestamp
                if record['score'] > existing['score']:
                    expected_data[key][str_id] = record
                elif record['score'] == existing['score']:
                    if record['ts'] < existing['ts']:
                        expected_data[key][str_id] = record

    # Format into TSV lines
    expected_files = {}
    for (lang, date), strings in expected_data.items():
        filename = f"{lang}_{date}.tsv"
        lines = []
        # Sort by str_id
        for str_id in sorted(strings.keys()):
            rec = strings[str_id]
            lines.append(f"{rec['str_id']}\t{rec['text']}\t{rec['score']}\n")
        expected_files[filename] = lines

    return expected_files

def test_aggregated_directory_exists():
    assert os.path.isdir(OUTPUT_DIR), f"Output directory {OUTPUT_DIR} does not exist."

def test_aggregated_files():
    expected_files = compute_expected_state()

    assert os.path.isdir(OUTPUT_DIR), f"Output directory {OUTPUT_DIR} does not exist."
    actual_files = set(os.listdir(OUTPUT_DIR))
    expected_filenames = set(expected_files.keys())

    # Check if there are any missing or extra files
    missing_files = expected_filenames - actual_files
    extra_files = actual_files - expected_filenames

    assert not missing_files, f"Missing expected TSV files: {missing_files}"
    assert not extra_files, f"Found unexpected files in output directory: {extra_files}"

    # Check contents of each file
    for filename, expected_lines in expected_files.items():
        filepath = os.path.join(OUTPUT_DIR, filename)
        with open(filepath, 'r', encoding='utf-8') as f:
            actual_lines = f.readlines()

        assert len(actual_lines) == len(expected_lines), \
            f"File {filename} has {len(actual_lines)} lines, expected {len(expected_lines)}."

        for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
            assert actual.rstrip('\r\n') == expected.rstrip('\r\n'), \
                f"Mismatch in {filename} at line {i+1}.\nExpected: {repr(expected)}\nActual: {repr(actual)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
