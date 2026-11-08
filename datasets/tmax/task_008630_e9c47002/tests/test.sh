#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

OUTPUT_FILE = "/home/user/processed_data.json"

EXPECTED_DATA = [
    {
        "id": 1,
        "category": "A",
        "status_code": "SYS-0001",
        "metric_name": "pressure_psi",
        "metric_value": 14.1
    },
    {
        "id": 1,
        "category": "A",
        "status_code": "SYS-0001",
        "metric_name": "temp_c",
        "metric_value": 22.5
    },
    {
        "id": 2,
        "category": "A",
        "status_code": "RUN-0002",
        "metric_name": "pressure_psi",
        "metric_value": 14.2
    },
    {
        "id": 2,
        "category": "A",
        "status_code": "RUN-0002",
        "metric_name": "temp_c",
        "metric_value": 22.7
    },
    {
        "id": 4,
        "category": "B",
        "status_code": "COL-1001",
        "metric_name": "pressure_psi",
        "metric_value": 15.5
    },
    {
        "id": 4,
        "category": "B",
        "status_code": "COL-1001",
        "metric_name": "temp_c",
        "metric_value": 18.0
    },
    {
        "id": 5,
        "category": "B",
        "status_code": "COL-1002",
        "metric_name": "pressure_psi",
        "metric_value": 15.4
    },
    {
        "id": 5,
        "category": "B",
        "status_code": "COL-1002",
        "metric_name": "temp_c",
        "metric_value": 18.1
    }
]

def test_output_file_exists():
    """Check if the processed_data.json file exists."""
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing. The script may not have run or saved to the wrong location."

def test_output_file_encoding_and_valid_json():
    """Check if the output file is valid UTF-8 and valid JSON."""
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."
    try:
        with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except UnicodeDecodeError:
        pytest.fail(f"File {OUTPUT_FILE} is not properly encoded in UTF-8.")
    except json.JSONDecodeError:
        pytest.fail(f"File {OUTPUT_FILE} does not contain valid JSON.")

    assert isinstance(data, list), "The JSON output should be an array of objects."

def test_output_data_content():
    """Check if the parsed JSON data exactly matches the expected output."""
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."

    with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
        data = json.load(f)

    assert len(data) == len(EXPECTED_DATA), f"Expected {len(EXPECTED_DATA)} rows, but got {len(data)} rows."

    # Sort both just in case, though the task implies a specific order from sorting
    def sort_key(row):
        return (row.get("category", ""), row.get("id", 0), row.get("metric_name", ""))

    sorted_data = sorted(data, key=sort_key)
    sorted_expected = sorted(EXPECTED_DATA, key=sort_key)

    for i, (actual_row, expected_row) in enumerate(zip(sorted_data, sorted_expected)):
        # Check types
        assert isinstance(actual_row.get("id"), int), f"Row {i}: 'id' should be an integer."
        assert isinstance(actual_row.get("metric_value"), float), f"Row {i}: 'metric_value' should be a float."
        assert isinstance(actual_row.get("category"), str), f"Row {i}: 'category' should be a string."
        assert isinstance(actual_row.get("status_code"), str), f"Row {i}: 'status_code' should be a string."
        assert isinstance(actual_row.get("metric_name"), str), f"Row {i}: 'metric_name' should be a string."

        # Check keys
        expected_keys = set(expected_row.keys())
        actual_keys = set(actual_row.keys())
        assert actual_keys == expected_keys, f"Row {i}: Expected keys {expected_keys}, got {actual_keys}."

        # Check values
        assert actual_row == expected_row, f"Row {i}: Data mismatch. Expected {expected_row}, got {actual_row}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
