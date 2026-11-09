#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import csv
import json
from collections import Counter
import pytest

DB_PATH = "/home/user/audit.db"
CSV_PATH = "/home/user/deadlock_risks.csv"
JSON_PATH = "/home/user/audit_logs.json"

EXPECTED_RECORDS = [
    {"tx_id": "tx01", "account_id": "A100", "start_time": 100, "end_time": 150, "operation": "UPDATE"},
    {"tx_id": "tx02", "account_id": "A100", "start_time": 140, "end_time": 160, "operation": "READ"},
    {"tx_id": "tx03", "account_id": "A100", "start_time": 170, "end_time": 200, "operation": "UPDATE"},
    {"tx_id": "tx04", "account_id": "A200", "start_time": 100, "end_time": 300, "operation": "UPDATE"},
    {"tx_id": "tx05", "account_id": "A200", "start_time": 250, "end_time": 350, "operation": "UPDATE"},
    {"tx_id": "tx06", "account_id": "A200", "start_time": 320, "end_time": 400, "operation": "READ"},
    {"tx_id": "tx07", "account_id": "A300", "start_time": 100, "end_time": 110, "operation": "UPDATE"},
    {"tx_id": "tx08", "account_id": "A400", "start_time": 500, "end_time": 600, "operation": "UPDATE"},
    {"tx_id": "tx09", "account_id": "A400", "start_time": 550, "end_time": 650, "operation": "UPDATE"},
    {"tx_id": "tx10", "account_id": "A400", "start_time": 620, "end_time": 700, "operation": "UPDATE"},
    {"tx_id": "tx11", "account_id": "A500", "start_time": 10, "end_time": 50, "operation": "UPDATE"},
    {"tx_id": "tx12", "account_id": "A500", "start_time": 40, "end_time": 80, "operation": "UPDATE"},
    {"tx_id": "tx13", "account_id": "A600", "start_time": 100, "end_time": 500, "operation": "UPDATE"},
    {"tx_id": "tx14", "account_id": "A600", "start_time": 200, "end_time": 300, "operation": "UPDATE"},
    {"tx_id": "tx15", "account_id": "A600", "start_time": 400, "end_time": 600, "operation": "UPDATE"},
    {"tx_id": "tx16", "account_id": "A700", "start_time": 1000, "end_time": 2000, "operation": "UPDATE"},
    {"tx_id": "tx17", "account_id": "A700", "start_time": 1500, "end_time": 2500, "operation": "UPDATE"},
    {"tx_id": "tx18", "account_id": "A800", "start_time": 1000, "end_time": 2000, "operation": "UPDATE"},
    {"tx_id": "tx19", "account_id": "A800", "start_time": 1500, "end_time": 2500, "operation": "UPDATE"},
    {"tx_id": "tx20", "account_id": "A900", "start_time": 1000, "end_time": 2000, "operation": "UPDATE"},
    {"tx_id": "tx21", "account_id": "A900", "start_time": 1500, "end_time": 2500, "operation": "UPDATE"}
]

FIELDS = ("tx_id", "account_id", "start_time", "end_time", "operation")

def record_tuple(record):
    return tuple(record[field] for field in FIELDS)

def read_csv():
    with open(CSV_PATH, "r", newline="", encoding="utf-8") as f:
        return list(csv.reader(f))

def test_database_exists():
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"
    assert os.path.isfile(DB_PATH), f"Path {DB_PATH} is not a file"

def test_transactions_table_schema():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(transactions);")
    columns = {row[1] for row in cursor.fetchall()}
    conn.close()

    expected_columns = {"tx_id", "account_id", "start_time", "end_time", "operation"}
    missing = expected_columns - columns
    assert not missing, f"The 'transactions' table is missing columns: {missing}"

def test_all_source_transactions_were_imported():
    assert os.path.isfile(JSON_PATH), f"Source JSON missing at {JSON_PATH}"
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        source_records = json.load(f)

    assert isinstance(source_records, list), "Source JSON must contain a list"
    assert Counter(record_tuple(r) for r in source_records) == Counter(
        record_tuple(r) for r in EXPECTED_RECORDS
    ), "The supplied source transaction log was altered"

    conn = sqlite3.connect(DB_PATH)
    try:
        db_records = conn.execute(
            "SELECT tx_id, account_id, start_time, end_time, operation FROM transactions"
        ).fetchall()
    finally:
        conn.close()

    expected = Counter(record_tuple(r) for r in source_records)
    actual = Counter(db_records)
    assert actual == expected, (
        "The transactions table does not contain exactly all source transactions. "
        f"Missing: {list((expected - actual).elements())}; "
        f"Unexpected/duplicate: {list((actual - expected).elements())}"
    )

def test_database_index_exists():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA index_list(transactions);")
    indexes = cursor.fetchall()

    found_valid_index = False
    for idx in indexes:
        index_name = idx[1]
        escaped_name = index_name.replace("'", "''")
        cursor.execute(f"PRAGMA index_info('{escaped_name}');")
        idx_cols = [row[2] for row in cursor.fetchall()]

        # Preserve the original assertion: both partitioning and sorting columns
        # must be covered by an index.
        if "account_id" in idx_cols and "start_time" in idx_cols:
            found_valid_index = True
            break

    conn.close()
    assert found_valid_index, "No index found on 'transactions' table covering 'account_id' and 'start_time'"

def test_csv_file_exists():
    assert os.path.exists(CSV_PATH), f"CSV file missing at {CSV_PATH}"
    assert os.path.isfile(CSV_PATH), f"Path {CSV_PATH} is not a file"

def test_csv_contents():
    expected_rows = [
        ["account_id", "current_tx", "next_tx"],
        ["A900", "tx20", "tx21"],
        ["A800", "tx18", "tx19"],
        ["A700", "tx16", "tx17"],
        ["A600", "tx13", "tx14"],
        ["A500", "tx11", "tx12"],
        ["A400", "tx08", "tx09"],
        ["A400", "tx09", "tx10"],
        ["A200", "tx04", "tx05"],
        ["A200", "tx05", "tx06"],
        ["A100", "tx01", "tx02"]
    ]

    actual_rows = read_csv()
    assert actual_rows == expected_rows, (
        f"CSV contents do not match expected results.\n"
        f"Expected: {expected_rows}\n"
        f"Actual: {actual_rows}"
    )

def test_csv_matches_window_analysis_of_imported_database():
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("""
            WITH chronological AS (
                SELECT
                    account_id,
                    tx_id AS current_tx,
                    end_time,
                    LEAD(tx_id) OVER (
                        PARTITION BY account_id ORDER BY start_time
                    ) AS next_tx,
                    LEAD(start_time) OVER (
                        PARTITION BY account_id ORDER BY start_time
                    ) AS next_start_time
                FROM transactions
            )
            SELECT account_id, current_tx, next_tx
            FROM chronological
            WHERE next_start_time < end_time
            ORDER BY account_id DESC, current_tx ASC
            LIMIT 10
        """).fetchall()
    finally:
        conn.close()

    expected_rows = [["account_id", "current_tx", "next_tx"]] + [list(row) for row in rows]
    actual_rows = read_csv()
    assert len(rows) == 10, f"Window analysis returned {len(rows)} rows instead of 10"
    assert actual_rows == expected_rows, (
        "CSV does not match a LEAD-based analysis of the imported transactions.\n"
        f"Expected from database: {expected_rows}\nActual: {actual_rows}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
