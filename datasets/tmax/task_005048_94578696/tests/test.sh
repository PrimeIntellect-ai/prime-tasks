#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_duplicates_csv():
    duplicates_path = "/home/user/duplicates.csv"
    assert os.path.isfile(duplicates_path), f"File {duplicates_path} does not exist. Did you run your Rust program?"

    with open(duplicates_path, 'r', newline='') as f:
        reader = csv.reader(f)
        data = list(reader)

    assert len(data) > 0, f"{duplicates_path} is empty."

    header = data[0]
    assert header == ['id1', 'id2'], f"Header in {duplicates_path} is incorrect. Expected ['id1', 'id2'], got {header}."

    actual_rows = data[1:]
    expected_rows = [
        ['1', '2'],
        ['4', '5'],
        ['6', '7'],
        ['7', '9'],
        ['10', '11']
    ]

    assert actual_rows == expected_rows, f"Data in {duplicates_path} is incorrect. Expected {expected_rows}, got {actual_rows}."

def test_cleaned_products_csv():
    cleaned_path = "/home/user/cleaned_products.csv"
    assert os.path.isfile(cleaned_path), f"File {cleaned_path} does not exist. Did you run your Rust program?"

    with open(cleaned_path, 'r', newline='') as f:
        reader = csv.reader(f)
        data = list(reader)

    assert len(data) > 0, f"{cleaned_path} is empty."

    header = data[0]
    assert header == ['id', 'description', 'price'], f"Header in {cleaned_path} is incorrect. Expected ['id', 'description', 'price'], got {header}."

    actual_rows = data[1:]
    expected_rows = [
        ['1', 'red mechanical keyboard cherry mx', '100.00'],
        ['2', 'red mechanical keyboard cherry mx switch', '105.00'],
        ['3', 'blue mechanical keyboard cherry mx', '95.00'],
        ['4', 'wireless optical mouse ergonomic', '30.00'],
        ['5', 'wireless optical mouse ergonomic usb', '30.00'],
        ['6', 'gaming monitor 144hz 1080p', '200.00'],
        ['7', 'gaming monitor 144hz 1080p ips', '210.00'],
        ['8', 'gaming monitor 144hz', '190.00'],
        ['9', 'gaming monitor 144hz 1080p ips vesa', '210.00'],
        ['10', 'usb c hub hdmi ethernet', '45.00'],
        ['11', 'usb c hub hdmi ethernet sd', '48.00'],
    ]

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in {cleaned_path}, but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} in {cleaned_path} is incorrect. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
