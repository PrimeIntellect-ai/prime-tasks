#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import pytest

DB_PATH = '/home/user/backup_catalog.db'
JSON_PATH = '/home/user/restore_plan.json'
TARGET_TIME = '2023-10-27 14:00:00'
TARGET_DB = 'auth_prod'

def get_expected_chain():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    query = """
    WITH RECURSIVE chain AS (
        SELECT 
            id, 
            id AS root_id,
            timestamp AS last_timestamp,
            size_mb,
            duration_sec,
            id AS path
        FROM backups
        WHERE db_name = ? AND backup_type = 'FULL' AND timestamp < ?

        UNION ALL

        SELECT 
            b.id,
            c.root_id,
            b.timestamp,
            c.size_mb + b.size_mb,
            c.duration_sec + b.duration_sec,
            c.path || ',' || b.id
        FROM backups b
        JOIN chain c ON b.parent_id = c.id
        WHERE b.timestamp < ?
    )
    SELECT path, size_mb, duration_sec, last_timestamp
    FROM chain
    ORDER BY last_timestamp DESC
    LIMIT 1;
    """

    c.execute(query, (TARGET_DB, TARGET_TIME, TARGET_TIME))
    result = c.fetchone()
    conn.close()

    if result:
        path_str, size_mb, duration_sec, _ = result
        return {
            "db_name": TARGET_DB,
            "target_time": TARGET_TIME,
            "chain": path_str.split(','),
            "total_size_mb": size_mb,
            "total_duration_sec": duration_sec
        }
    return None

def test_json_file_exists():
    assert os.path.exists(JSON_PATH), f"The expected output file {JSON_PATH} does not exist."
    assert os.path.isfile(JSON_PATH), f"The path {JSON_PATH} is not a file."

def test_json_contents():
    expected_data = get_expected_chain()
    assert expected_data is not None, "Could not compute expected chain from the database."

    with open(JSON_PATH, 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_PATH} does not contain valid JSON.")

    assert "db_name" in actual_data, "Missing 'db_name' in JSON output."
    assert actual_data["db_name"] == expected_data["db_name"], f"Expected db_name '{expected_data['db_name']}', got '{actual_data['db_name']}'."

    assert "target_time" in actual_data, "Missing 'target_time' in JSON output."
    assert actual_data["target_time"] == expected_data["target_time"], f"Expected target_time '{expected_data['target_time']}', got '{actual_data['target_time']}'."

    assert "chain" in actual_data, "Missing 'chain' in JSON output."
    assert isinstance(actual_data["chain"], list), "'chain' must be a list of backup IDs."
    assert actual_data["chain"] == expected_data["chain"], f"Expected chain {expected_data['chain']}, got {actual_data['chain']}."

    assert "total_size_mb" in actual_data, "Missing 'total_size_mb' in JSON output."
    assert actual_data["total_size_mb"] == expected_data["total_size_mb"], f"Expected total_size_mb {expected_data['total_size_mb']}, got {actual_data['total_size_mb']}."

    assert "total_duration_sec" in actual_data, "Missing 'total_duration_sec' in JSON output."
    assert actual_data["total_duration_sec"] == expected_data["total_duration_sec"], f"Expected total_duration_sec {expected_data['total_duration_sec']}, got {actual_data['total_duration_sec']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
