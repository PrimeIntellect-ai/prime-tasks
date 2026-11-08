#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import unicodedata

def compute_expected_clean_records(raw_file_path):
    assert os.path.exists(raw_file_path), f"Input file {raw_file_path} is missing."

    records = []
    with open(raw_file_path, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))

    groups = {}
    for record in records:
        norm_text = unicodedata.normalize('NFC', record['text']).strip().lower()
        key = (record['user'], norm_text)
        if key not in groups:
            groups[key] = []
        groups[key].append(record)

    deduped = []
    for key, group in groups.items():
        # Sort by timestamp ascending, then id ascending
        group_sorted = sorted(group, key=lambda x: (x['timestamp'], x['id']))
        deduped.append(group_sorted[0])

    # Final sort
    deduped_sorted = sorted(deduped, key=lambda x: (x['timestamp'], x['id']))
    return records, deduped_sorted

def test_reviews_clean_content():
    raw_file_path = "/home/user/reviews_raw.jsonl"
    clean_file_path = "/home/user/reviews_clean.jsonl"

    assert os.path.exists(clean_file_path), f"Output file {clean_file_path} is missing."

    _, expected_clean = compute_expected_clean_records(raw_file_path)

    actual_clean = []
    with open(clean_file_path, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                try:
                    actual_clean.append(json.loads(line))
                except json.JSONDecodeError:
                    assert False, f"Line in {clean_file_path} is not valid JSON: {line}"

    assert len(actual_clean) == len(expected_clean), f"Expected {len(expected_clean)} records in {clean_file_path}, but found {len(actual_clean)}."

    for i, (actual, expected) in enumerate(zip(actual_clean, expected_clean)):
        assert actual == expected, f"Record at index {i} in {clean_file_path} does not match expected.\nExpected: {expected}\nActual: {actual}"

def test_report_content():
    raw_file_path = "/home/user/reviews_raw.jsonl"
    report_file_path = "/home/user/report.txt"

    assert os.path.exists(report_file_path), f"Report file {report_file_path} is missing."

    raw_records, expected_clean = compute_expected_clean_records(raw_file_path)

    total_in = len(raw_records)
    total_out = len(expected_clean)
    duplicates = total_in - total_out

    expected_report = (
        "ETL Cleanup Report\n"
        f"Total Input Records: {total_in}\n"
        f"Total Valid Records: {total_out}\n"
        f"Duplicates Removed: {duplicates}\n"
    )

    with open(report_file_path, "r", encoding="utf-8") as f:
        actual_report = f.read()

    assert actual_report.strip() == expected_report.strip(), (
        f"Content of {report_file_path} does not match expected.\n"
        f"Expected:\n{expected_report}\n"
        f"Actual:\n{actual_report}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
