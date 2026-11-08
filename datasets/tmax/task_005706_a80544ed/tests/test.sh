#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import re

def test_metrics_csv_exists_and_format():
    metrics_file = "/home/user/metrics_5min.csv"
    assert os.path.exists(metrics_file), f"Output file {metrics_file} is missing."
    assert os.path.isfile(metrics_file), f"Path {metrics_file} is not a file."

    with open(metrics_file, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['bucket_time', 'request_count', 'avg_response_time', 'error_rate_pct'], \
            "The header of metrics_5min.csv is incorrect or missing."

        rows = list(reader)
        assert len(rows) == 3, f"Expected 3 data rows in metrics_5min.csv, found {len(rows)}."

        # Expected data
        expected_data = [
            ("2023-10-01T10:00:00Z", 4, 130.12, 25.0),
            ("2023-10-01T10:05:00Z", 2, 305.25, 50.0),
            ("2023-10-01T10:10:00Z", 4, 113.75, 50.0),
        ]

        # Check sorting and values
        for i, (row, expected) in enumerate(zip(rows, expected_data)):
            assert row[0] == expected[0], f"Row {i+1}: Expected bucket_time {expected[0]}, got {row[0]}"
            assert int(row[1]) == expected[1], f"Row {i+1}: Expected request_count {expected[1]}, got {row[1]}"
            assert abs(float(row[2]) - expected[2]) < 0.01, f"Row {i+1}: Expected avg_response_time {expected[2]}, got {row[2]}"
            assert abs(float(row[3]) - expected[3]) < 0.01, f"Row {i+1}: Expected error_rate_pct {expected[3]}, got {row[3]}"

def test_pipeline_log_exists_and_content():
    log_file = "/home/user/pipeline.log"
    assert os.path.exists(log_file), f"Log file {log_file} is missing."
    assert os.path.isfile(log_file), f"Path {log_file} is not a file."

    with open(log_file, 'r') as f:
        content = f.read()

    expected_log = "SUCCESS - Processed 10 input rows. Generated 3 output buckets."
    assert expected_log in content, f"Expected log line '{expected_log}' not found in {log_file}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
