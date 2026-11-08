#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_optimal_dt_csv_exists():
    """Test that the optimal_dt.csv file was created."""
    csv_path = "/home/user/optimal_dt.csv"
    assert os.path.isfile(csv_path), f"File {csv_path} does not exist. The script must create this file."

def test_optimal_dt_csv_content():
    """Test that the optimal_dt.csv contains the correct headers and values."""
    csv_path = "/home/user/optimal_dt.csv"

    if not os.path.isfile(csv_path):
        pytest.fail("Cannot test content because optimal_dt.csv is missing.")

    expected_results = {
        "1": "0.550",
        "2": "0.275",
        "3": "1.000",
        "4": "0.350",
        "5": "0.450"
    }

    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail("The CSV file is empty.")

        assert [h.strip() for h in headers] == ["id", "max_dt"], "The CSV headers must be exactly 'id' and 'max_dt'."

        rows = list(reader)
        assert len(rows) == len(expected_results), f"Expected {len(expected_results)} rows, but found {len(rows)}."

        seen_ids = set()
        for row in rows:
            assert len(row) == 2, f"Row {row} does not have exactly 2 columns."
            row_id = row[0].strip()
            max_dt = row[1].strip()

            assert row_id in expected_results, f"Unexpected id '{row_id}' found in CSV."
            assert row_id not in seen_ids, f"Duplicate id '{row_id}' found in CSV."
            seen_ids.add(row_id)
            assert max_dt == expected_results[row_id], f"Expected max_dt '{expected_results[row_id]}' for id '{row_id}', but got '{max_dt}'."

        assert seen_ids == set(expected_results), "The CSV must contain every expected parameter ID exactly once."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
