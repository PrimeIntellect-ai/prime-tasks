#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import re
import pytest

RAW_FILE = "/home/user/data/raw_metrics.csv"
CLEAN_FILE = "/home/user/output/clean_long.csv"
SUMMARY_FILE = "/home/user/output/summary.txt"

def get_expected_data():
    """Parse the raw file and compute the expected output dynamically."""
    assert os.path.isfile(RAW_FILE), f"Raw file {RAW_FILE} is missing."

    with open(RAW_FILE, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)

        dropped_count = 0
        valid_rows = []
        for row in reader:
            # Check for embedded newlines in any field
            if any('\n' in col or '\r' in col for col in row):
                dropped_count += 1
            else:
                valid_rows.append(row)

    records = []
    for row in valid_rows:
        ts, host, cpu, mem, disk, notes = row

        # Normalize date
        if re.match(r'^\d{4}/\d{2}/\d{2}$', ts):
            date = ts.replace('/', '-')
        elif re.match(r'^\d{2}-\d{2}-\d{4}$', ts):
            m, d, y = ts.split('-')
            date = f"{y}-{m}-{d}"
        else:
            date = ts

        records.append([date, host, 'cpu_load', cpu])
        records.append([date, host, 'disk_io', disk])
        records.append([date, host, 'memory_usage', mem])

    # Sort chronologically by date, then host, then alphabetically by metric_name
    records.sort(key=lambda x: (x[0], x[1], x[2]))

    return dropped_count, len(records), records

def test_output_directories_exist():
    """Ensure the output directory exists."""
    output_dir = "/home/user/output"
    assert os.path.isdir(output_dir), f"Directory {output_dir} was not created or is missing."

def test_clean_long_csv_content():
    """Validate the contents, reshaping, normalization, and sorting of clean_long.csv."""
    assert os.path.isfile(CLEAN_FILE), f"Output file {CLEAN_FILE} is missing."

    _, _, expected_records = get_expected_data()

    with open(CLEAN_FILE, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"{CLEAN_FILE} is empty.")

        assert header == ["date", "host", "metric_name", "metric_value"], \
            f"Incorrect header in {CLEAN_FILE}: {header}"

        actual_records = [row for row in reader]

    assert len(actual_records) == len(expected_records), \
        f"Expected {len(expected_records)} data rows in {CLEAN_FILE}, found {len(actual_records)}."

    for i, (actual, expected) in enumerate(zip(actual_records, expected_records)):
        assert actual == expected, \
            f"Row {i+1} mismatch in {CLEAN_FILE}.\nExpected: {expected}\nActual: {actual}"

def test_summary_txt_content():
    """Validate the execution summary text file."""
    assert os.path.isfile(SUMMARY_FILE), f"Summary file {SUMMARY_FILE} is missing."

    expected_dropped, expected_total, _ = get_expected_data()

    expected_content = (
        "Pipeline Execution Summary\n"
        "--------------------------\n"
        f"Dropped invalid rows: {expected_dropped}\n"
        f"Total valid metric records generated: {expected_total}\n"
    )

    with open(SUMMARY_FILE, "r", encoding="utf-8") as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), \
        f"Content mismatch in {SUMMARY_FILE}.\nExpected:\n{expected_content}\nActual:\n{actual_content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
