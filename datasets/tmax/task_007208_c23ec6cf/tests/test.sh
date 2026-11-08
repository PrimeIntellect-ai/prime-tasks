#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import io
import os
import sqlite3
import subprocess
from collections import Counter

import pytest

SCRIPT_PATH = '/home/user/process_config.sh'
DB_PATH = '/home/user/cmdb_tracking.db'
EXPORT_GLOB = '/home/user/cmdb_exports/*.csv'


def expected_records():
    records = []
    paths = sorted(glob.glob(EXPORT_GLOB))
    assert paths, 'No CSV exports found'

    for path in paths:
        raw = open(path, 'rb').read()
        try:
            text = raw.decode('utf-8')
        except UnicodeDecodeError:
            text = raw.decode('iso-8859-1')

        reader = csv.reader(io.StringIO(text, newline=''))
        header = next(reader)
        assert header and header[0] == 'Timestamp'

        for row in reader:
            if not row:
                continue
            assert len(row) == len(header), f'Malformed row in {path}: {row!r}'
            date = row[0][:10]
            for server, status in zip(header[1:], row[1:]):
                records.append((date, server, status))

    return records


def read_records():
    assert os.path.isfile(DB_PATH), f'Database not found at {DB_PATH}'
    conn = sqlite3.connect(DB_PATH)
    try:
        return conn.execute('SELECT date, server, status FROM daily_status').fetchall()
    finally:
        conn.close()


@pytest.fixture(scope='session', autouse=True)
def execute_script_twice():
    assert os.path.isfile(SCRIPT_PATH), f'Script not found at {SCRIPT_PATH}'
    assert os.access(SCRIPT_PATH, os.X_OK), f'Script at {SCRIPT_PATH} is not executable'

    expected = expected_records()
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    first = subprocess.run(
        [SCRIPT_PATH], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=30
    )
    assert first.returncode == 0, f'First script execution failed:\n{first.stdout}'
    first_rows = read_records()
    assert Counter(first_rows) == Counter(expected), \
        f'First execution did not import the complete CSV contents. Expected {Counter(expected)!r}, got {Counter(first_rows)!r}'

    second = subprocess.run(
        [SCRIPT_PATH], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=30
    )
    assert second.returncode == 0, f'Second script execution failed:\n{second.stdout}'
    second_rows = read_records()
    assert Counter(second_rows) == Counter(expected), \
        f'Script is not idempotent. Expected {Counter(expected)!r}, got {Counter(second_rows)!r}'

    return expected


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f'Script not found at {SCRIPT_PATH}'
    assert os.access(SCRIPT_PATH, os.X_OK), f'Script at {SCRIPT_PATH} is not executable'


def test_db_exists():
    assert os.path.isfile(DB_PATH), f'Database not found at {DB_PATH}'


def test_db_schema():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='daily_status';")
    table_exists = cursor.fetchone()
    assert table_exists, "Table 'daily_status' does not exist in the database"

    cursor.execute('PRAGMA table_info(daily_status);')
    table_info = cursor.fetchall()
    columns = {row[1]: row[2].upper() for row in table_info}

    assert 'date' in columns, "Column 'date' missing from 'daily_status'"
    assert 'server' in columns, "Column 'server' missing from 'daily_status'"
    assert 'status' in columns, "Column 'status' missing from 'daily_status'"
    assert table_info == [
        (0, 'date', 'TEXT', 0, None, 0),
        (1, 'server', 'TEXT', 0, None, 0),
        (2, 'status', 'TEXT', 0, None, 0),
    ], f'Unexpected daily_status schema: {table_info!r}'

    conn.close()


def test_all_db_records(execute_script_twice):
    actual = read_records()
    assert Counter(actual) == Counter(execute_script_twice), \
        f'Database contents do not exactly match all reshaped CSV records: {Counter(actual)!r}'


def test_db_records():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Check total count
    cursor.execute('SELECT count(*) FROM daily_status;')
    count = cursor.fetchone()[0]
    assert count == 9, f'Expected 9 records in daily_status, found {count}'

    # Check UTF-8 conversion and specific record
    cursor.execute("SELECT count(*) FROM daily_status WHERE status = 'Dégradé';")
    degrade_count = cursor.fetchone()[0]
    assert degrade_count == 1, f"Expected 1 record with status 'Dégradé', found {degrade_count}. This might indicate an issue with character encoding."

    # Check formatting and data extraction
    cursor.execute('SELECT date, server, status FROM daily_status ORDER BY date, server, status LIMIT 1;')
    first_row = cursor.fetchone()
    expected_first_row = ('2023-10-01', 'Server1', 'Actif')
    assert first_row == expected_first_row, f'Expected first ordered row to be {expected_first_row}, found {first_row}'

    # Check another specific row to ensure time was stripped
    cursor.execute("SELECT count(*) FROM daily_status WHERE date = '2023-10-02' AND server = 'Server2' AND status = 'Actif';")
    week2_count = cursor.fetchone()[0]
    assert week2_count == 1, 'Expected 1 record for 2023-10-02, Server2, Actif. Ensure time portion of timestamp is discarded.'

    conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
