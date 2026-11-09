#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import pytest

def test_snakefile_exists():
    """Verify that the Snakefile exists."""
    snakefile_path = "/home/user/Snakefile"
    assert os.path.exists(snakefile_path) and os.path.isfile(snakefile_path), "Snakefile is missing in /home/user/"

def test_features_csv():
    """Verify the features.csv file has the correct headers and row count."""
    csv_path = "/home/user/features.csv"
    assert os.path.exists(csv_path), f"Missing output file: {csv_path}"

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail(f"{csv_path} is empty")

        assert headers == ['ip', 'method', 'endpoint'], f"Incorrect headers in {csv_path}: {headers}"

        row_count = sum(1 for _ in reader)
        assert row_count == 400, f"Expected 400 data rows in {csv_path}, found {row_count}"

def test_threats_json():
    """Verify the threats.json file has the exact expected counts."""
    json_path = "/home/user/threats.json"
    assert os.path.exists(json_path), f"Missing output file: {json_path}"

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} is not valid JSON")

    expected = {
        "10.0.0.55": 400
    }

    assert data == expected, f"Content of {json_path} does not match expected output. Got: {data}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
