#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_cleaned_weather_data():
    output_file = '/home/user/cleaned_weather.csv'

    assert os.path.exists(output_file), f"The output file {output_file} was not found."
    assert os.path.isfile(output_file), f"{output_file} is not a file."

    with open(output_file, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "The output file is empty."

    header = rows[0]
    expected_header = ['station_id', 'station_name', 'date', 'temperature']
    assert header == expected_header, f"Expected header {expected_header}, got {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 9, f"Expected exactly 9 data rows, got {len(data_rows)}"

    expected_data = [
        ['1', 'Pariś', '2023-01-01', '5.0'],
        ['1', 'París', '2023-01-02', '7.0'],
        ['1', 'París', '2023-01-03', '9.0'],
        ['1', 'París', '2023-01-04', '9.0'],
        ['2', 'München', '2023-01-01', '-1.0'],
        ['2', 'München', '2023-01-02', '-1.0'],
        ['2', 'München', '2023-01-03', '-3.0'],
        ['2', 'München', '2023-01-04', '-5.0'],
        ['2', 'München', '2023-01-05', '-7.0']
    ]

    for i, (actual, expected) in enumerate(zip(data_rows, expected_data)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
