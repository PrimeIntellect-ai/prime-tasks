#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_matches_csv_exists_and_correct():
    path = '/home/user/matches.csv'
    assert os.path.isfile(path), f"File {path} does not exist. The task requires creating this file."

    expected_rows = [
        {"A_id": "A1", "B_doc_id": "B12"},
        {"A_id": "A2", "B_doc_id": "B10"},
        {"A_id": "A3", "B_doc_id": "B11"}
    ]

    with open(path, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"File {path} is empty.")

        assert header == ["A_id", "B_doc_id"], f"Header in {path} is incorrect. Expected ['A_id', 'B_doc_id'], got {header}."

        rows = list(reader)
        assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in {path}, got {len(rows)}."

        for i, expected in enumerate(expected_rows):
            assert rows[i] == [expected["A_id"], expected["B_doc_id"]], (
                f"Row {i+1} is incorrect. Expected {expected['A_id']},{expected['B_doc_id']}, "
                f"got {rows[i][0]},{rows[i][1]}."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
