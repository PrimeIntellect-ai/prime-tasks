#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import json
import math

CSV_PATH = "/home/user/processed_logs.csv"
DB_PATH = "/home/user/logs.db"
RAW_PATH = "/home/user/raw_logs.txt"


def expected_rows_from_raw():
    raw_rows = []
    with open(RAW_PATH, "r", encoding="utf-8") as f:
        for line_number, line in enumerate(f):
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("|", 5)
            assert len(parts) == 6, f"Malformed raw input on line {line_number + 1}: {line}"
            timestamp, ip, endpoint, status, response_time, payload = parts
            raw_rows.append({
                "timestamp": timestamp,
                "ip": ip,
                "endpoint": endpoint,
                "status": int(status),
                "response_time": int(response_time),
                "payload": payload,
                "input_order": line_number,
            })

    # Processing is chronological, with original file order as a deterministic tie-breaker.
    raw_rows.sort(key=lambda row: (row["timestamp"], row["input_order"]))

    seen = set()
    cleaned = []
    for row in raw_rows:
        key = (row["ip"], row["endpoint"], row["payload"])
        if key in seen:
            continue
        seen.add(key)
        if row["response_time"] < 0:
            continue
        cleaned.append(row)

    endpoint_windows = {}
    expected = []
    for row in cleaned:
        window = endpoint_windows.setdefault(row["endpoint"], [])
        window.append(row["response_time"])
        if len(window) > 3:
            del window[0]
        rolling_avg = math.floor(sum(window) / len(window))
        expected.append((
            row["timestamp"],
            row["ip"],
            row["endpoint"],
            row["status"],
            row["response_time"],
            rolling_avg,
            row["payload"],
        ))
    return expected


def read_csv_rows():
    rows = []
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        for line_number, line in enumerate(f, 1):
            line = line.rstrip("\r\n")
            if not line:
                continue
            parts = line.split(",", 6)
            assert len(parts) == 7, f"Row {line_number} in CSV does not have exactly 7 columns: {line}"
            try:
                status = int(parts[3])
                response_time = int(parts[4])
                rolling_avg = int(parts[5])
            except ValueError as exc:
                raise AssertionError(f"Row {line_number} has a non-integer numeric field: {line}") from exc
            try:
                json.loads(parts[6])
            except json.JSONDecodeError as exc:
                raise AssertionError(f"Row {line_number} has invalid JSON payload: {parts[6]}") from exc
            rows.append((parts[0], parts[1], parts[2], status, response_time, rolling_avg, parts[6]))
    return rows


def test_files_exist():
    assert os.path.isfile(CSV_PATH), f"The processed CSV file {CSV_PATH} is missing."
    assert os.path.isfile(DB_PATH), f"The SQLite database file {DB_PATH} is missing."


def test_csv_format_and_content():
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 7, f"Expected 7 rows in the CSV, but found {len(lines)}."

    for i, line in enumerate(lines):
        parts = line.split(",", 6)
        assert len(parts) == 7, f"Row {i+1} in CSV does not have exactly 7 columns: {line}"
        payload = parts[6].strip()
        assert payload.startswith("{") and payload.endswith("}"), f"Row {i+1} payload does not look like valid JSON: {payload}"


def test_csv_exactly_matches_raw_processing():
    expected = expected_rows_from_raw()
    actual = read_csv_rows()
    assert actual == expected, f"Processed CSV does not match the required cleaning, chronological deduplication, and rolling computation. Expected {expected}, got {actual}."


def test_database_schema():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT type FROM sqlite_master WHERE name='metrics';")
    object_row = cursor.fetchone()
    assert object_row is not None and object_row[0] == "table", "'metrics' must be an SQLite table."

    cursor.execute("PRAGMA table_info(metrics);")
    columns = {row[1]: row[2].upper() for row in cursor.fetchall()}

    expected_columns = {
        "timestamp": "TEXT",
        "ip": "TEXT",
        "endpoint": "TEXT",
        "status": "INTEGER",
        "response_time": "INTEGER",
        "rolling_avg": "INTEGER",
        "payload": "TEXT"
    }

    for col, ctype in expected_columns.items():
        assert col in columns, f"Column '{col}' is missing from the 'metrics' table."
        assert ctype in columns[col] or columns[col] == "", f"Column '{col}' should be of type {ctype}, found {columns[col]}."

    conn.close()


def test_database_row_count():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM metrics;")
    count = cursor.fetchone()[0]
    assert count == 7, f"Expected 7 rows in the 'metrics' table, but found {count}."
    conn.close()


def test_database_rolling_averages():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT rolling_avg FROM metrics WHERE endpoint='/api/v1/users' ORDER BY timestamp;")
    users_avg = [row[0] for row in cursor.fetchall()]
    expected_users_avg = [150, 175, 200, 250, 216]
    assert users_avg == expected_users_avg, f"Rolling averages for /api/v1/users are incorrect. Expected {expected_users_avg}, got {users_avg}."

    cursor.execute("SELECT rolling_avg FROM metrics WHERE endpoint='/api/v1/data' ORDER BY timestamp;")
    data_avg = [row[0] for row in cursor.fetchall()]
    expected_data_avg = [300, 350]
    assert data_avg == expected_data_avg, f"Rolling averages for /api/v1/data are incorrect. Expected {expected_data_avg}, got {data_avg}."

    conn.close()


def test_database_deduplication_and_filtering():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT COUNT(*) FROM metrics WHERE response_time < 0;")
    negative_count = cursor.fetchone()[0]
    assert negative_count == 0, "Found rows with negative response_time, which should have been filtered out."

    cursor.execute("SELECT ip, endpoint, payload, COUNT(*) FROM metrics GROUP BY ip, endpoint, payload HAVING COUNT(*) > 1;")
    duplicates = cursor.fetchall()
    assert len(duplicates) == 0, f"Found duplicate entries based on IP, ENDPOINT, and PAYLOAD: {duplicates}"

    conn.close()


def test_database_exactly_matches_raw_and_csv():
    expected = expected_rows_from_raw()
    csv_rows = read_csv_rows()

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT timestamp, ip, endpoint, status, response_time, rolling_avg, payload FROM metrics ORDER BY timestamp, rowid;")
    database_rows = cursor.fetchall()
    conn.close()

    assert database_rows == expected, f"Database contents do not match the rows derived from the raw logs. Expected {expected}, got {database_rows}."
    assert database_rows == csv_rows, "The metrics table is not an exact import of processed_logs.csv."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
