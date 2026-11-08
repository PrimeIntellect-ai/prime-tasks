#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import math
import pytest

OUTPUT_FILE = '/home/user/ml_dataset.csv'
RAW_DATA_DIR = '/home/user/raw_data'

def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."

def test_output_file_content_and_format():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."

    expected_rows = []
    for i in range(1, 51):
        filename = os.path.join(RAW_DATA_DIR, f'sample_{i:03d}.txt')
        if not os.path.isfile(filename):
            continue

        with open(filename, 'r') as f:
            values = [float(line.strip()) for line in f if line.strip()]

        exact_sum = math.fsum(values)
        analytical_limit = i * 1000.5

        if abs(exact_sum - analytical_limit) <= 1e-7:
            expected_rows.append((i, f"{exact_sum:.4f}"))

    actual_rows = []
    with open(OUTPUT_FILE, 'r') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"The file {OUTPUT_FILE} is empty.")

        assert header == ['sample_id', 'total_energy'], f"Header row is incorrect. Expected ['sample_id', 'total_energy'], got {header}"

        for row in reader:
            if not row:
                continue
            assert len(row) == 2, f"Row {row} does not have exactly 2 columns."

            # Check 4 decimal places formatting
            energy_str = row[1]
            assert '.' in energy_str and len(energy_str.split('.')[1]) == 4, f"Energy value {energy_str} is not formatted to exactly 4 decimal places."

            actual_rows.append((int(row[0]), energy_str))

    # Check sorting
    sample_ids = [r[0] for r in actual_rows]
    assert sample_ids == sorted(sample_ids), "The rows are not sorted by sample_id in ascending order."

    # Compare exact rows
    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} valid rows, but got {len(actual_rows)}. Make sure corrupted files are excluded."

    for actual, expected in zip(actual_rows, expected_rows):
        assert actual == expected, f"Row mismatch. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
