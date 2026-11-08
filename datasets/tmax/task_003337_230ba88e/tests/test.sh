#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import gzip
import csv

def test_category_metrics_compressed_file():
    gz_file_path = "/home/user/category_metrics.csv.gz"

    # Check if the file exists
    assert os.path.isfile(gz_file_path), f"The compressed file {gz_file_path} does not exist."

    # Read the compressed file
    try:
        with gzip.open(gz_file_path, 'rt', newline='') as f:
            reader = csv.reader(f)
            rows = list(reader)
    except Exception as e:
        assert False, f"Failed to read {gz_file_path} as a gzip-compressed CSV file. Error: {e}"

    # Check the header
    assert len(rows) > 0, "The CSV file is empty."
    assert rows[0] == ["category", "mean_similarity"], f"Incorrect header. Expected ['category', 'mean_similarity'], got {rows[0]}"

    # Check the data and sorting
    expected_data = [
        ["alpha", "0.9273"],
        ["beta", "1.0000"],
        ["gamma", "0.9845"]
    ]

    data_rows = rows[1:]
    assert len(data_rows) == len(expected_data), f"Expected {len(expected_data)} data rows, got {len(data_rows)}."

    for i, (actual, expected) in enumerate(zip(data_rows, expected_data)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
