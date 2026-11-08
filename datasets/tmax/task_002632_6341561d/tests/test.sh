#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import json
import pytest

def test_processed_data_csv():
    path = "/home/user/output/processed_data.csv"
    assert os.path.isfile(path), f"Expected output file {path} does not exist."

    with open(path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['tx_id', 'user_id', 'first_name', 'last_name', 'email', 'amount', 'is_anomaly'], \
            "CSV header does not match expected columns."

        rows = list(reader)

    assert len(rows) == 9, f"Expected 9 records in {path}, found {len(rows)}."

    # Sort rows by tx_id to ensure order-independent checking
    rows_sorted = sorted(rows, key=lambda x: x[0])

    expected_rows = [
        ['t1', '1', 'Alice', '***', '***@example.com', '10.0', 'False'],
        ['t10', '4', 'Diana', '***', '***@hero.com', '21.0', 'False'],
        ['t11', '4', 'Diana', '***', '***@hero.com', '22.0', 'False'],
        ['t2', '1', 'Alice', '***', '***@example.com', '12.0', 'False'],
        ['t3', '1', 'Alice', '***', '***@example.com', '100.0', 'True'],
        ['t5', '3', 'Charlie', '***', '***@domain.com', '5.0', 'False'],
        ['t7', '3', 'Charlie', '***', '***@domain.com', '6.0', 'False'],
        ['t8', '3', 'Charlie', '***', '***@domain.com', '7.0', 'False'],
        ['t9', '4', 'Diana', '***', '***@hero.com', '20.0', 'False']
    ]

    for actual, expected in zip(rows_sorted, expected_rows):
        # We allow float comparison for amount by converting string to float
        assert actual[0:5] == expected[0:5], f"Row mismatch for tx_id {expected[0]}"
        assert float(actual[5]) == float(expected[5]), f"Amount mismatch for tx_id {expected[0]}"
        assert actual[6].lower() == expected[6].lower(), f"Anomaly flag mismatch for tx_id {expected[0]}"

def test_summary_json():
    path = "/home/user/output/summary.json"
    assert os.path.isfile(path), f"Expected output file {path} does not exist."

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    assert "total_valid_records" in data, "Key 'total_valid_records' missing in summary.json."
    assert "total_anomalies" in data, "Key 'total_anomalies' missing in summary.json."

    assert data["total_valid_records"] == 9, f"Expected 9 valid records, got {data['total_valid_records']}."
    assert data["total_anomalies"] == 1, f"Expected 1 anomaly, got {data['total_anomalies']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
