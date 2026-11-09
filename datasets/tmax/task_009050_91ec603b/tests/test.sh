#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import io
from decimal import Decimal, InvalidOperation

def test_clean_data_csv():
    raw_path = "/home/user/raw_data.jsonl"
    clean_path = "/home/user/clean_data.csv"

    assert os.path.exists(clean_path), f"File {clean_path} is missing."

    # Compute expected state based on the raw data
    records = {}
    with open(raw_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            data = json.loads(line)
            ts = data['timestamp']
            mid = data['metric_id'].lower()
            # Overwrites previous entries, effectively keeping the LAST occurrence
            records[(ts, mid)] = {
                'timestamp': ts,
                'metric_id': mid,
                'value': data['value'],
                'message': data['message']
            }

    # Sort by timestamp, then metric_id
    sorted_keys = sorted(records.keys(), key=lambda x: (x[0], x[1]))
    expected_rows = [records[k] for k in sorted_keys]

    # Parse the submitted CSV so numerically equivalent JSON number renderings such
    # as 50 and 50.0 are both accepted. jq legitimately emits 50 for JSON 50.0.
    with open(clean_path, 'r', encoding='utf-8', newline='') as f:
        try:
            actual_rows = list(csv.reader(f, strict=True))
        except csv.Error as exc:
            raise AssertionError(f"clean_data.csv is not valid CSV: {exc}")

    assert len(actual_rows) == len(expected_rows), (
        "The number of rows in clean_data.csv does not match the expected output."
    )

    for index, (actual, expected) in enumerate(zip(actual_rows, expected_rows), start=1):
        assert len(actual) == 4, f"CSV row {index} must contain exactly four columns."
        assert actual[0] == expected['timestamp'], f"Incorrect timestamp in CSV row {index}."
        assert actual[1] == expected['metric_id'], f"Incorrect metric_id in CSV row {index}."
        assert actual[3] == expected['message'], f"Incorrect message in CSV row {index}."
        try:
            actual_value = Decimal(actual[2])
            expected_value = Decimal(str(expected['value']))
        except InvalidOperation:
            raise AssertionError(f"CSV row {index} has a non-numeric value.")
        assert actual_value.is_finite() and actual_value == expected_value, (
            f"Incorrect value in CSV row {index}."
        )

def test_report_txt():
    raw_path = "/home/user/raw_data.jsonl"
    report_path = "/home/user/report.txt"

    assert os.path.exists(report_path), f"File {report_path} is missing."

    # Recompute the expected metrics and count
    records = {}
    with open(raw_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            data = json.loads(line)
            ts = data['timestamp']
            mid = data['metric_id'].lower()
            records[(ts, mid)] = True

    count = len(records)
    unique_metrics = sorted(list(set([k[1] for k in records.keys()])))
    metrics_str = ",".join(unique_metrics)

    expected_report = (
        "ETL Cleanup Report\n"
        "------------------\n"
        f"Total Clean Records: {count}\n"
        f"Unique Metrics: {metrics_str}"
    )

    with open(report_path, 'r', encoding='utf-8') as f:
        actual_report = f.read().strip()

    assert actual_report == expected_report, (
        "The content of report.txt does not match the expected output. "
        "Ensure the template is exactly as specified, the count is correct, "
        "and the unique metrics are comma-separated and alphabetically sorted."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
