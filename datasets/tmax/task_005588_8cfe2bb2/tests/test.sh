#!/bin/bash
mkdir -p /logs/verifier

if python3 - <<'PY'
import csv
import os
import re
import sqlite3
import subprocess
from collections import defaultdict
from pathlib import Path

HOME = Path('/home/user')
SOURCE = HOME / 'data' / 'sales.csv'
REPORT = HOME / 'report.csv'
DB = HOME / 'sales.db'
PROGRAM = HOME / 'analyzer.go'
MODULE = HOME / 'go.mod'
BINARY = Path('/tmp/analyzer-under-test')
HEADER = ['tx_id', 'user_id', 'amount', 'timestamp', 'moving_avg']

# Preserve all original existence assertions.
assert PROGRAM.exists(), 'The Go program /home/user/analyzer.go does not exist.'
assert PROGRAM.is_file(), '/home/user/analyzer.go is not a file.'
assert DB.exists(), 'The SQLite database /home/user/sales.db does not exist.'
assert REPORT.exists(), 'The output file /home/user/report.csv does not exist.'
assert REPORT.is_file(), '/home/user/report.csv is not a file.'
assert MODULE.exists(), 'Go module was not initialized in /home/user (go.mod is missing).'

source_text = PROGRAM.read_text(errors='replace')
source_lower = source_text.lower()
assert re.search(r'\bavg\s*\(', source_lower), 'The Go source does not contain an SQL AVG calculation.'
assert re.search(r'\bover\s*\(', source_lower), 'The moving average is not expressed as an SQL window calculation.'
assert ('query(' in source_lower or 'querycontext(' in source_lower or 'prepare(' in source_lower), 'The Go source does not execute or prepare an SQL query.'
placeholder_count = source_text.count('?')
numbered = all(re.search(r'\$' + str(i) + r'\b', source_text) for i in range(1, 4))
named = all(re.search(r'[@:$]' + name + r'\b', source_text, re.I) for name in ('min', 'limit', 'offset'))
assert placeholder_count >= 3 or numbered or named, 'The SQL query does not contain placeholders for min, limit, and offset.'

build_env = os.environ.copy()
build_env['CGO_ENABLED'] = '1'
subprocess.run(['go', 'build', '-o', str(BINARY), '.'], cwd=HOME, env=build_env, check=True, timeout=180)
assert BINARY.is_file(), 'Building analyzer.go did not produce an executable.'

original_csv = SOURCE.read_bytes()

def run_program(minimum, limit, offset):
    subprocess.run([
        str(BINARY), '-min', str(minimum), '-limit', str(limit), '-offset', str(offset)
    ], cwd=HOME, check=True, timeout=60)
    assert DB.exists(), 'The program did not create /home/user/sales.db.'
    assert REPORT.exists() and REPORT.is_file(), 'The program did not create /home/user/report.csv.'


def read_report_raw():
    with REPORT.open(newline='') as f:
        return [row for row in csv.reader(f) if row]


def read_input():
    with SOURCE.open(newline='') as f:
        return list(csv.DictReader(f))


def expected_for(rows, minimum, limit, offset):
    by_user = defaultdict(list)
    for row in rows:
        by_user[row['user_id']].append(row)
    calculated = []
    for user_rows in by_user.values():
        user_rows.sort(key=lambda r: r['timestamp'])
        for index, row in enumerate(user_rows):
            window = user_rows[max(0, index - 2):index + 1]
            moving = sum(float(item['amount']) for item in window) / len(window)
            if float(row['amount']) > minimum:
                calculated.append((row, moving))
    calculated.sort(key=lambda item: (item[0]['user_id'], item[0]['timestamp']))
    return calculated[offset:offset + limit]


def assert_semantic_report(rows, minimum, limit, offset):
    actual = read_report_raw()
    assert actual and actual[0] == HEADER, f'Incorrect report header: {actual[0] if actual else None}'
    expected = expected_for(rows, minimum, limit, offset)
    assert len(actual) == len(expected) + 1, f'Expected {len(expected)} data rows, found {max(0, len(actual)-1)}.'
    for position, (actual_row, (input_row, moving)) in enumerate(zip(actual[1:], expected), 1):
        assert len(actual_row) == 5, f'Output row {position} has {len(actual_row)} columns.'
        assert actual_row[0] == input_row['tx_id']
        assert actual_row[1] == input_row['user_id']
        assert abs(float(actual_row[2]) - float(input_row['amount'])) < 1e-9
        assert actual_row[3] == input_row['timestamp']
        assert re.fullmatch(r'-?\d+\.\d{2}', actual_row[4]), f'moving_avg is not formatted to two decimals: {actual_row[4]}'
        assert abs(float(actual_row[4]) - round(moving + 1e-12, 2)) < 0.005


def assert_database_loaded(rows):
    connection = sqlite3.connect(DB)
    try:
        tables = [r[0] for r in connection.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]
        expected = sorted((r['tx_id'], r['user_id'], float(r['amount']), r['timestamp']) for r in rows)
        found = False
        for table in tables:
            escaped = table.replace('"', '""')
            columns = [r[1] for r in connection.execute(f'PRAGMA table_info("{escaped}")')]
            if all(name in columns for name in ('tx_id', 'user_id', 'amount', 'timestamp')):
                values = sorted((str(a), str(b), float(c), str(d)) for a, b, c, d in connection.execute(
                    f'SELECT tx_id, user_id, amount, timestamp FROM "{escaped}"'
                ))
                if values == expected:
                    found = True
                    break
        assert found, 'sales.db does not contain a table loaded with exactly the input CSV transactions.'
    finally:
        connection.close()

try:
    # Execute the requested invocation and retain the original exact-content assertion.
    run_program(30.0, 6, 2)
    expected_rows = [
        ['tx_id', 'user_id', 'amount', 'timestamp', 'moving_avg'],
        ['t06', 'u2', '80.0', '2023-01-02T11:00:00Z', '50.00'],
        ['t07', 'u2', '40.0', '2023-01-03T11:00:00Z', '46.67'],
        ['t08', 'u2', '90.0', '2023-01-04T11:00:00Z', '70.00'],
        ['t09', 'u3', '100.0', '2023-01-01T12:00:00Z', '100.00'],
        ['t11', 'u3', '105.0', '2023-01-03T12:00:00Z', '73.33'],
    ]
    actual_rows = read_report_raw()
    assert len(actual_rows) == len(expected_rows), f'Expected {len(expected_rows)} rows in report.csv (including header), but found {len(actual_rows)}.'
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f'Row {i+1} mismatch. Expected {expected}, got {actual}.'
    assert_database_loaded(read_input())

    # Replace the input with verifier-created data and exercise different flag values.
    generated = [
        ['q91', 'acct_c', '18.5', '2025-03-04T09:00:00Z'],
        ['q92', 'acct_c', '81.7', '2025-03-05T09:00:00Z'],
        ['q93', 'acct_c', '44.2', '2025-03-06T09:00:00Z'],
        ['q94', 'acct_c', '103.6', '2025-03-07T09:00:00Z'],
        ['r21', 'acct_a', '62.4', '2025-01-01T12:00:00Z'],
        ['r22', 'acct_a', '11.3', '2025-01-02T12:00:00Z'],
        ['r23', 'acct_a', '95.8', '2025-01-03T12:00:00Z'],
        ['r24', 'acct_a', '37.9', '2025-01-04T12:00:00Z'],
        ['s71', 'acct_b', '50.1', '2024-11-10T15:30:00Z'],
        ['s72', 'acct_b', '72.6', '2024-11-11T15:30:00Z'],
        ['s73', 'acct_b', '9.4', '2024-11-12T15:30:00Z'],
        ['s74', 'acct_b', '88.2', '2024-11-13T15:30:00Z'],
    ]
    with SOURCE.open('w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['tx_id', 'user_id', 'amount', 'timestamp'])
        writer.writerows(generated)

    generated_rows = read_input()
    run_program(17.25, 7, 1)
    assert_semantic_report(generated_rows, 17.25, 7, 1)
    assert_database_loaded(generated_rows)

    run_program(51.0, 4, 2)
    assert_semantic_report(generated_rows, 51.0, 4, 2)
finally:
    SOURCE.write_bytes(original_csv)

PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
