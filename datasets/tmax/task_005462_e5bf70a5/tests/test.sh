#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import pytest

EXPECTED_ROWS = [
    ("A01", "A02", "attr_category", 1.0),
    ("A01", "A02", "attr_color", 0.67),
    ("A01", "B01", "attr_category", 1.0),
    ("A01", "B01", "attr_taste", 1.0),
    ("A02", "B01", "attr_category", 1.0),
    ("A02", "C01", "attr_color", 0.5),
    ("C01", "C02", "attr_category", 1.0),
    ("C01", "C02", "attr_taste", 1.0),
]

def test_similarities_csv():
    csv_path = "/home/user/similarities.csv"
    assert os.path.isfile(csv_path), f"File {csv_path} does not exist."

    with open(csv_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    parsed_rows = []
    for line in lines:
        parts = line.split(",")
        assert len(parts) == 4, f"Invalid CSV line format: {line}"
        parsed_rows.append((parts[0], parts[1], parts[2], float(parts[3])))

    parsed_rows.sort()

    assert len(parsed_rows) == len(EXPECTED_ROWS), f"Expected {len(EXPECTED_ROWS)} rows in CSV, found {len(parsed_rows)}."

    for expected, actual in zip(EXPECTED_ROWS, parsed_rows):
        assert expected[0] == actual[0], f"Expected item_1 {expected[0]}, got {actual[0]}"
        assert expected[1] == actual[1], f"Expected item_2 {expected[1]}, got {actual[1]}"
        assert expected[2] == actual[2], f"Expected attribute {expected[2]}, got {actual[2]}"
        assert abs(expected[3] - actual[3]) < 0.01, f"Expected score {expected[3]}, got {actual[3]}"

def test_inventory_db():
    db_path = "/home/user/inventory.db"
    assert os.path.isfile(db_path), f"Database {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check if table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='similarity_network';")
    assert cursor.fetchone() is not None, "Table 'similarity_network' does not exist in the database."

    # Fetch rows
    cursor.execute("SELECT item_1, item_2, attribute, score FROM similarity_network ORDER BY item_1, item_2, attribute;")
    rows = cursor.fetchall()

    conn.close()

    assert len(rows) == len(EXPECTED_ROWS), f"Expected {len(EXPECTED_ROWS)} rows in database, found {len(rows)}."

    for expected, actual in zip(EXPECTED_ROWS, rows):
        assert expected[0] == actual[0], f"Expected item_1 {expected[0]}, got {actual[0]}"
        assert expected[1] == actual[1], f"Expected item_2 {expected[1]}, got {actual[1]}"
        assert expected[2] == actual[2], f"Expected attribute {expected[2]}, got {actual[2]}"
        assert abs(expected[3] - float(actual[3])) < 0.01, f"Expected score {expected[3]}, got {actual[3]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
