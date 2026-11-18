#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3

def test_validation_errors_json():
    json_path = '/home/user/validation_errors.json'
    assert os.path.isfile(json_path), f"Expected output file {json_path} does not exist."

    with open(json_path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} does not contain valid JSON."

    expected_data = [
        {
            "lang": "es",
            "string_key": "welcome",
            "reason": "placeholder_mismatch"
        },
        {
            "lang": "fr",
            "string_key": "goodbye",
            "reason": "empty_string"
        },
        {
            "lang": "it",
            "string_key": "welcome",
            "reason": "not_in_db"
        }
    ]

    assert isinstance(data, list), "JSON root must be a list."
    assert data == expected_data, (
        f"Contents of {json_path} do not match the expected output. "
        f"Expected: {expected_data}, Got: {data}"
    )

def test_database_final_state():
    db_path = '/home/user/translations.db'
    assert os.path.isfile(db_path), f"Database file {db_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT lang, string_key, translated_text, updated_at FROM strings ORDER BY id")
    rows = cursor.fetchall()
    conn.close()

    expected_rows = [
        ('fr', 'welcome', 'Bonjour %s sur %s', '2023-10-02T10:00:00Z'),
        ('fr', 'goodbye', 'Au revoir', '2023-01-01T00:00:00Z'),
        ('es', 'welcome', 'Bienvenido %s a %s', '2023-01-01T00:00:00Z'),
        ('es', 'goodbye', 'Adios', '2023-01-01T00:00:00Z'),
        ('de', 'error', 'Fehlercode %s', '2023-10-01T10:00:00Z')
    ]

    # Check updated rows
    assert rows[0] == expected_rows[0], f"Expected fr/welcome to be updated correctly. Got: {rows[0]}"
    assert rows[4] == expected_rows[4], f"Expected de/error to be updated correctly. Got: {rows[4]}"

    # Check unchanged rows
    assert rows[1] == expected_rows[1], f"Expected fr/goodbye to remain unchanged. Got: {rows[1]}"
    assert rows[2] == expected_rows[2], f"Expected es/welcome to remain unchanged. Got: {rows[2]}"
    assert rows[3] == expected_rows[3], f"Expected es/goodbye to remain unchanged. Got: {rows[3]}"

    assert len(rows) == 5, f"Expected exactly 5 rows in the strings table, found {len(rows)}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
