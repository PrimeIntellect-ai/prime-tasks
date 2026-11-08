#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import sqlite3
import subprocess

DB_PATH = "/home/user/db/time_series.db"
SCRIPT_PATH = "/home/user/process_data.py"
RAW_DIR = "/home/user/raw_data"

EXPECTED_ROWS = [
    ("2023-10-01 10:00:00", "S1", 22.5),
    ("2023-10-01 10:00:00", "S2", 23.1),
    ("2023-10-01 10:05:00", "S1", 22.7),
    ("2023-10-01 10:05:00", "S2", 23.2),
    ("2023-10-01 10:10:00", "S1", 22.9),
]

def test_db_exists():
    assert os.path.isfile(DB_PATH), f"Database file does not exist at {DB_PATH}"

def test_table_exists():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='readings';")
    assert cursor.fetchone() is not None, "Table 'readings' does not exist in the database."
    conn.close()

def test_schema_constraints():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Check for unique index on (timestamp, device_id)
    cursor.execute("PRAGMA index_list('readings');")
    indexes = cursor.fetchall()

    is_unique = False
    for index in indexes:
        if index[2] == 1:  # unique index
            cursor.execute(f"PRAGMA index_info('{index[1]}');")
            cols = [row[2] for row in cursor.fetchall()]
            if set(cols) == {'timestamp', 'device_id'}:
                is_unique = True
                break

    # Also check if it's a composite primary key
    if not is_unique:
        cursor.execute("PRAGMA table_info('readings');")
        cols = cursor.fetchall()
        pk_cols = [col[1] for col in cols if col[5] > 0]
        if set(pk_cols) == {'timestamp', 'device_id'}:
            is_unique = True

    conn.close()
    assert is_unique, "No UNIQUE constraint or PRIMARY KEY on (timestamp, device_id) found in 'readings' table schema."

def test_data_count_and_content():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT timestamp, device_id, temperature FROM readings ORDER BY timestamp, device_id;")
    rows = cursor.fetchall()
    conn.close()

    assert len(rows) == 5, f"Expected exactly 5 records (deduplicated), but got {len(rows)}."

    for actual, expected in zip(rows, EXPECTED_ROWS):
        assert actual == expected, f"Record mismatch. Expected {expected}, got {actual}."

def test_script_exists_and_is_python():
    assert os.path.isfile(SCRIPT_PATH), f"ETL script does not exist at {SCRIPT_PATH}"
    assert os.path.getsize(SCRIPT_PATH) > 0, "ETL script is empty"
    subprocess.run(
        ["python3", "-m", "py_compile", SCRIPT_PATH],
        check=True,
        timeout=30,
        cwd="/home/user",
    )

def _read_state():
    conn = sqlite3.connect(DB_PATH)
    try:
        integrity = conn.execute("PRAGMA integrity_check;").fetchone()[0]
        schema = conn.execute(
            "SELECT type, name, tbl_name, sql FROM sqlite_master "
            "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name;"
        ).fetchall()
        rows = conn.execute(
            "SELECT timestamp, device_id, temperature "
            "FROM readings ORDER BY timestamp, device_id;"
        ).fetchall()
        return integrity, schema, rows
    finally:
        conn.close()

def _run_script():
    subprocess.run(
        ["python3", SCRIPT_PATH],
        check=True,
        timeout=60,
        cwd="/home/user",
    )

def test_pipeline_rebuilds_database_and_is_idempotent():
    # Add an unpredictable UTF-16LE input using one of the documented schemas.
    # The duplicate has a different temperature, so the first reading must be kept.
    token = secrets.token_hex(8)
    device_id = f"S{secrets.randbelow(800) + 100}"
    day = secrets.randbelow(20) + 2
    hour = secrets.randbelow(10) + 1
    minute = secrets.randbelow(60)
    source_timestamp = f"11/{day:02d}/2024 {hour:02d}:{minute:02d} AM"
    normalized_timestamp = f"2024-11-{day:02d} {hour:02d}:{minute:02d}:00"
    probe_path = os.path.join(RAW_DIR, f"probe_{token}.csv")
    probe = (
        "Timestamp,Temperature,Info\n"
        f"{source_timestamp},31.25,device_id: {device_id} | battery: 77\n"
        f"{source_timestamp},99.75,device_id: {device_id} | battery: 76\n"
    )
    with open(probe_path, "wb") as f:
        f.write(probe.encode("utf-16le"))

    # Force the submitted script to perform the ETL rather than relying on the
    # database that was present when verification began.
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    for suffix in ("-wal", "-shm", "-journal"):
        sidecar = DB_PATH + suffix
        if os.path.exists(sidecar):
            os.remove(sidecar)

    _run_script()
    assert os.path.isfile(DB_PATH), "Running process_data.py did not create the database"

    integrity, schema, rows = _read_state()
    assert integrity == "ok", f"Rebuilt database failed integrity check: {integrity}"

    expected = sorted(
        EXPECTED_ROWS + [(normalized_timestamp, device_id, 31.25)],
        key=lambda row: (row[0], row[1]),
    )
    assert rows == expected, (
        "Executing process_data.py from a clean database did not produce the "
        "expected normalized, deduplicated readings"
    )

    first_state = (integrity, schema, rows)
    _run_script()
    second_state = _read_state()
    assert second_state == first_state, "A second execution changed the database state"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
