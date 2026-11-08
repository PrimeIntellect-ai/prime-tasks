#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_deadlock_victims_file():
    file_path = "/home/user/deadlock_victims.csv"
    assert os.path.exists(file_path), f"Output file {file_path} was not created."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    with open(file_path, "r", newline='') as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail("The CSV file is empty.")

        assert headers == ["cycle_members", "victim_tx"], \
            f"Expected headers ['cycle_members', 'victim_tx'], but got {headers}"

        rows = list(reader)

        assert len(rows) == 2, f"Expected exactly 2 data rows, but got {len(rows)}."

        expected_records = {
            ("T1-T2-T3", "T3"),
            ("T4-T5", "T5")
        }

        actual_records = set(tuple(row) for row in rows)

        assert actual_records == expected_records, \
            f"Expected records {expected_records}, but got {actual_records}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
