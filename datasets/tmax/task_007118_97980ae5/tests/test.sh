#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import pytest

PREDICTIONS_FILE = "/home/user/predictions.csv"

def test_predictions_file_exists():
    assert os.path.isfile(PREDICTIONS_FILE), f"The file {PREDICTIONS_FILE} does not exist. Ensure your script saves the output to the correct path."

def test_predictions_content():
    assert os.path.isfile(PREDICTIONS_FILE), "Predictions file is missing."

    with open(PREDICTIONS_FILE, "r") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"The file {PREDICTIONS_FILE} is empty.")

        assert header == ["ID", "Prediction"], f"Expected header ['ID', 'Prediction'], but got {header}"

        rows = list(reader)

    assert len(rows) == 3, f"Expected exactly 3 valid rows, but found {len(rows)}."

    # Check sorting by ID
    ids = [row[0] for row in rows]
    assert ids == sorted(ids), "The rows are not sorted alphabetically by ID."

    # Expected truth data derived from task logic
    expected = {
        "SUB001": "0.4280",
        "SUB003": "0.9619",
        "SUB005": "0.6985"
    }

    actual = {row[0]: row[1] for row in rows}

    for expected_id, expected_pred in expected.items():
        assert expected_id in actual, f"Expected ID {expected_id} is missing from the predictions."
        assert actual[expected_id] == expected_pred, f"Prediction for {expected_id} is incorrect. Expected {expected_pred}, got {actual[expected_id]}. Check rounding and math."

    for actual_id in actual:
        assert actual_id in expected, f"Unexpected ID {actual_id} found in predictions. Ensure invalid rows are filtered correctly."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
