#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3


def get_expected_data():
    # These expectations are fixed from the original input fixtures rather than
    # recomputed from agent-writable files.
    assert os.path.exists('/home/user/telemetry.csv'), "Input file /home/user/telemetry.csv is missing."
    assert os.path.exists('/home/user/users.json'), "Input file /home/user/users.json is missing."

    return [
        ('u3', 'view', '2023-10-01T10:10:00Z', 'US', 'Basic'),
        ('u1', 'login', '2023-10-01T10:00:00Z', 'US', 'Free'),
        ('u4', 'login', '2023-10-01T10:20:00Z', 'AP', 'Free'),
        ('u1', 'logout', '2023-10-01T10:50:00Z', 'US', 'Free'),
        ('u2', 'click', '2023-10-01T10:05:00Z', 'EU', 'Premium'),
        ('u5', 'login', '2023-10-01T10:30:00Z', 'US', 'Premium'),
    ]


def test_database_exists():
    db_file = '/home/user/cleaned_sample.db'
    assert os.path.exists(db_file), f"Database file {db_file} does not exist."
    assert os.path.isfile(db_file), f"Path {db_file} is not a file."


def test_table_schema_and_content():
    db_file = '/home/user/cleaned_sample.db'
    assert os.path.exists(db_file), "Database file missing."

    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='telemetry_sample';")
    table_exists = cursor.fetchone()
    assert table_exists is not None, "Table 'telemetry_sample' does not exist in the database."

    cursor.execute("PRAGMA table_info(telemetry_sample);")
    columns_info = cursor.fetchall()

    expected_columns = [
        ('user_id', 'TEXT'),
        ('event_type', 'TEXT'),
        ('timestamp', 'TEXT'),
        ('region', 'TEXT'),
        ('subscription_tier', 'TEXT')
    ]
    actual_columns = [(col[1], col[2].upper()) for col in columns_info]

    actual_col_names = [col[0] for col in actual_columns]
    expected_col_names = [col[0] for col in expected_columns]
    assert actual_col_names == expected_col_names, f"Column names or order incorrect. Expected {expected_col_names}, got {actual_col_names}."
    assert actual_columns == expected_columns, f"Column schema incorrect. Expected {expected_columns}, got {actual_columns}."

    cursor.execute("SELECT user_id, event_type, timestamp, region, subscription_tier FROM telemetry_sample ORDER BY subscription_tier, timestamp, user_id;")
    actual_data = cursor.fetchall()
    conn.close()

    expected_data = get_expected_data()
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} rows in telemetry_sample, got {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, f"Row {i} mismatch. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
