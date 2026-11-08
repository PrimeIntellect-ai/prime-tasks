#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_category_stats_exists():
    """Verify that the output file exists."""
    file_path = '/home/user/category_stats.csv'
    assert os.path.exists(file_path), f"The output file {file_path} is missing."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

def test_category_stats_content_and_encoding():
    """Verify the encoding, header, and exact contents of the output file."""
    file_path = '/home/user/category_stats.csv'

    expected_rows = [
        ['Category', 'Valid_Review_Count', 'Average_Rating'],
        ['Books', '822', '3.02'],
        ['Clothing', '803', '3.02'],
        ['Toys', '801', '2.96'],
        ['Home', '795', '2.99'],
        ['Electronics', '767', '3.04']
    ]

    actual_rows = []
    try:
        with open(file_path, 'r', encoding='utf-8', newline='') as f:
            reader = csv.reader(f)
            for row in reader:
                actual_rows.append(row)
    except UnicodeDecodeError:
        pytest.fail(f"The file {file_path} is not properly UTF-8 encoded.")
    except Exception as e:
        pytest.fail(f"Failed to read {file_path}: {e}")

    assert len(actual_rows) > 0, "The output CSV file is empty."

    assert actual_rows[0] == expected_rows[0], (
        f"Header mismatch. Expected {expected_rows[0]}, got {actual_rows[0]}"
    )

    assert len(actual_rows) == len(expected_rows), (
        f"Row count mismatch. Expected {len(expected_rows)} rows (including header), "
        f"got {len(actual_rows)}."
    )

    for i in range(1, len(expected_rows)):
        assert actual_rows[i] == expected_rows[i], (
            f"Row {i} mismatch. Expected {expected_rows[i]}, got {actual_rows[i]}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
