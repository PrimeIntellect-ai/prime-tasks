#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import csv
import os
from collections import Counter

def test_clean_output_mse():
    output_path = '/app/clean_output.csv'
    assert os.path.isfile(output_path), f"Expected output file {output_path} is missing."

    expected = {
        "2023-10-01T12:00:00Z": 12.5000,
        "2023-10-01T12:01:00Z": 13.0000,
        "2023-10-01T12:02:00Z": 13.5000,
        "2023-10-01T12:03:00Z": 15.1667,
        "2023-10-01T12:04:00Z": 16.1667,
    }

    sq_errors = []
    count = 0
    matched_times = []

    with open(output_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames is not None, "CSV header is missing."
        assert 'time' in reader.fieldnames, "Column 'time' is missing in the output CSV."
        assert 'smoothed_value' in reader.fieldnames, "Column 'smoothed_value' is missing in the output CSV."

        for row in reader:
            t = row['time']
            if t in expected:
                try:
                    v = float(row['smoothed_value'])
                except ValueError:
                    assert False, f"Could not parse smoothed_value '{row['smoothed_value']}' as float for time {t}."

                sq_errors.append((v - expected[t])**2)
                matched_times.append(t)
                count += 1

    assert count == len(expected), f"Expected {len(expected)} matching rows, but found {count}."

    timestamp_counts = Counter(matched_times)
    assert all(timestamp_counts[t] == 1 for t in expected), \
        f"Each expected timestamp must appear exactly once; found counts {dict(timestamp_counts)}."

    mse = sum(sq_errors) / count
    threshold = 0.001

    assert mse < threshold, f"MSE {mse:.6f} is not strictly less than the threshold {threshold}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
