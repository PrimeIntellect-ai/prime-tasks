#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import sqlite3
import pytest

DB_PATH = "/home/user/backup_catalog.db"
JSON_PATH = "/home/user/restore_plan.json"

EXPECTED_JOBS = [
    (1, "full", "success", 1600000000),
    (2, "inc", "success", 1600086400),
    (3, "full", "failed", 1600172800),
    (4, "full", "success", 1600259200),
    (5, "inc", "failed", 1600345600),
    (6, "inc", "success", 1600432000),
    (7, "inc", "success", 1600518400),
]

EXPECTED_FILES = [
    (1, 1, 50000),
    (2, 2, 500),
    (3, 4, 60000),
    (4, 5, 600),
    (5, 6, 1200),
    (6, 7, 800),
]


def test_json_file_exists():
    assert os.path.exists(JSON_PATH), f"JSON file {JSON_PATH} does not exist."
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} is not a regular file."


def test_catalog_data_unchanged():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} missing."
    conn = sqlite3.connect(DB_PATH)
    try:
        jobs = conn.execute(
            "SELECT id, type, status, start_time FROM jobs ORDER BY id"
        ).fetchall()
        files = conn.execute(
            "SELECT id, job_id, size_bytes FROM files ORDER BY id"
        ).fetchall()
    finally:
        conn.close()

    assert jobs == EXPECTED_JOBS, "The jobs catalog data was modified."
    assert files == EXPECTED_FILES, "The files catalog data was modified."


def test_json_content_and_logic():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} missing."

    # Compute the expected result dynamically, after catalog integrity is checked.
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("""
        SELECT id, start_time
        FROM jobs
        WHERE type='full' AND status='success'
        ORDER BY start_time DESC
        LIMIT 1
    """)
    full_backup = cursor.fetchone()
    assert full_backup is not None, "No successful full backup found in the database."
    full_backup_id, full_start_time = full_backup

    cursor.execute("""
        SELECT id
        FROM jobs
        WHERE type='inc' AND status='success' AND start_time > ?
        ORDER BY start_time ASC
    """, (full_start_time,))
    inc_backups = cursor.fetchall()
    inc_backup_ids = [row[0] for row in inc_backups]

    all_ids = [full_backup_id] + inc_backup_ids
    placeholders = ",".join(["?"] * len(all_ids))
    cursor.execute(f"""
        SELECT SUM(size_bytes)
        FROM files
        WHERE job_id IN ({placeholders})
    """, all_ids)
    total_size = cursor.fetchone()[0] or 0
    conn.close()

    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} does not contain valid JSON.")

    assert "full_backup_id" in data, "Missing 'full_backup_id' key in JSON."
    assert "incremental_backup_ids" in data, "Missing 'incremental_backup_ids' key in JSON."
    assert "total_files_size" in data, "Missing 'total_files_size' key in JSON."

    assert data["full_backup_id"] == full_backup_id, \
        f"Expected full_backup_id {full_backup_id}, got {data['full_backup_id']}."
    assert isinstance(data["incremental_backup_ids"], list), \
        "'incremental_backup_ids' must be a list."
    assert data["incremental_backup_ids"] == inc_backup_ids, \
        f"Expected incremental_backup_ids {inc_backup_ids}, got {data['incremental_backup_ids']}."
    assert data["total_files_size"] == total_size, \
        f"Expected total_files_size {total_size}, got {data['total_files_size']}."


def test_index_created():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} missing."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("""
        SELECT count(*)
        FROM sqlite_master
        WHERE type='index' AND tbl_name='jobs' AND name NOT LIKE 'sqlite_autoindex%';
    """)
    count = cursor.fetchone()[0]
    assert count > 0, "No custom index was created on the 'jobs' table."

    cursor.execute("""
        SELECT name
        FROM sqlite_master
        WHERE type='index' AND tbl_name='jobs' AND name NOT LIKE 'sqlite_autoindex%'
    """)
    index_names = [row[0] for row in cursor.fetchall()]

    suitable = []
    for index_name in index_names:
        escaped_name = index_name.replace("'", "''")
        rows = cursor.execute(f"PRAGMA index_xinfo('{escaped_name}')").fetchall()
        key_columns = [row[2] for row in rows if row[5] == 1 and row[1] >= 0]
        if (len(key_columns) >= 3
                and set(key_columns[:2]) == {"status", "type"}
                and key_columns[2] == "start_time"):
            suitable.append(index_name)

    conn.close()
    assert suitable, (
        "No suitable composite jobs index found. Its leading columns must be "
        "status and type (in either order), followed by start_time."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
