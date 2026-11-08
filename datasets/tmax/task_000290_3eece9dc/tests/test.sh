#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile

DB_PATH = "/home/user/incidents.db"
LOG_PATH = "/home/user/app_logs.raw"
SCRIPT_PATH = "/home/user/process_logs.py"


def test_database_exists():
    """Test that the SQLite database was created at the correct location."""
    assert os.path.isfile(DB_PATH), f"Database file not found at {DB_PATH}"


def test_table_schema():
    """Test that the 'errors' table exists and has the correct columns and types."""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='errors'")
    table = c.fetchone()
    assert table is not None, "Table 'errors' does not exist in the database."

    c.execute("PRAGMA table_info(errors)")
    columns_info = c.fetchall()

    column_names = [col[1] for col in columns_info]
    expected_columns = ["timestamp", "ip", "endpoint", "status"]

    for col in expected_columns:
        assert col in column_names, f"Column '{col}' is missing from the 'errors' table."

    declared_types = {col[1]: col[2].upper() for col in columns_info}
    expected_types = {
        "timestamp": "TEXT",
        "ip": "TEXT",
        "endpoint": "TEXT",
        "status": "INTEGER",
    }
    for name, expected_type in expected_types.items():
        assert declared_types[name] == expected_type, (
            f"Column '{name}' must have type {expected_type}, "
            f"got {declared_types[name] or 'no declared type'}."
        )

    conn.close()


def test_database_records():
    """Test that the 'errors' table contains exactly the expected records (status >= 400)."""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    c.execute("SELECT count(*) FROM errors")
    count = c.fetchone()[0]
    assert count == 4, f"Expected 4 error records in the 'errors' table, got {count}."

    c.execute("SELECT timestamp, ip, endpoint, status FROM errors ORDER BY timestamp ASC")
    rows = c.fetchall()

    expected = [
        ("2023-10-14T12:01:15Z", "10.0.0.5", "/api/v1/auth", 401),
        ("2023-10-14T12:03:05Z", "172.16.0.4", "/admin/config", 403),
        ("2023-10-14T12:04:50Z", "10.0.0.8", "/api/v1/missing", 404),
        ("2023-10-14T12:05:10Z", "192.168.1.105", "/api/v1/status", 500)
    ]

    assert rows == expected, f"Expected records {expected}, but got {rows}."

    conn.close()


def test_script_exists_and_processes_fresh_utf16le_input():
    assert os.path.exists(SCRIPT_PATH), f"Processing script not found at {SCRIPT_PATH}"
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file"

    token = secrets.token_hex(12)
    records = [
        {"time": "2042-06-01T09:04:00Z", "client": f"client-low-{token}",
         "request": f"/ignored/{token}", "status": 399, "user_agent": "test"},
        {"time": "2042-06-01T09:03:00Z", "client": f"client-400-{token}",
         "request": f"/unicode/é/{token}", "status": 400, "user_agent": "test"},
        {"time": "2042-06-01T09:01:00Z", "client": f"client-ok-{token}",
         "request": f"/ok/{token}", "status": 201, "user_agent": "test"},
        {"time": "2042-06-01T09:02:00Z", "client": f"client-503-{token}",
         "request": f"/failure/{token}", "status": 503, "user_agent": "test"},
        {"time": "2042-06-01T09:05:00Z", "client": f"client-418-{token}",
         "request": f"/teapot/{token}", "status": 418, "user_agent": "test"},
    ]
    expected = sorted(
        [
            (r["time"], r["client"], r["request"], r["status"])
            for r in records if r["status"] >= 400
        ],
        key=lambda row: row[0],
    )

    with tempfile.TemporaryDirectory() as backup_dir:
        log_backup = os.path.join(backup_dir, "app_logs.raw")
        db_backup = os.path.join(backup_dir, "incidents.db")
        shutil.copy2(LOG_PATH, log_backup)
        shutil.copy2(DB_PATH, db_backup)

        try:
            with open(LOG_PATH, "w", encoding="utf-16le") as f:
                for record in records:
                    f.write(json.dumps(record, ensure_ascii=False) + "\n")

            os.remove(DB_PATH)
            result = subprocess.run(
                ["python3", SCRIPT_PATH],
                cwd="/home/user",
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
            assert result.returncode == 0, (
                f"Processing script failed with exit code {result.returncode}.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            assert os.path.isfile(DB_PATH), "Script did not create /home/user/incidents.db"
            assert os.path.isfile(SCRIPT_PATH), "Processing script removed itself during execution"

            conn = sqlite3.connect(DB_PATH)
            try:
                c = conn.cursor()
                c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='errors'")
                assert c.fetchone() is not None, "Script did not create the errors table"

                c.execute("PRAGMA table_info(errors)")
                columns_info = c.fetchall()
                declared_types = {col[1]: col[2].upper() for col in columns_info}
                required_types = {
                    "timestamp": "TEXT",
                    "ip": "TEXT",
                    "endpoint": "TEXT",
                    "status": "INTEGER",
                }
                for name, expected_type in required_types.items():
                    assert name in declared_types, f"Column '{name}' is missing after script execution"
                    assert declared_types[name] == expected_type, (
                        f"Column '{name}' must have type {expected_type}, "
                        f"got {declared_types[name] or 'no declared type'}"
                    )

                c.execute("SELECT timestamp, ip, endpoint, status FROM errors ORDER BY timestamp ASC")
                actual = c.fetchall()
                assert actual == expected, (
                    "Script did not derive the expected error rows from the fresh UTF-16LE input. "
                    f"Expected {expected}, got {actual}."
                )
            finally:
                conn.close()
        finally:
            shutil.copy2(log_backup, LOG_PATH)
            if os.path.exists(DB_PATH):
                os.remove(DB_PATH)
            shutil.copy2(db_backup, DB_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
