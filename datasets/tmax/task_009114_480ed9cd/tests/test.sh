#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/audit_instrument

cat << 'PY_EOF' > /tmp/audit_instrument/sitecustomize.py
import json
import os
import sqlite3

_original_connect = sqlite3.connect
_trace_path = os.environ.get('AUDIT_SQL_TRACE')

class TracedConnection(sqlite3.Connection):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if _trace_path:
            def record(statement):
                with open(_trace_path, 'a', encoding='utf-8') as trace_file:
                    trace_file.write(json.dumps(statement) + '\n')
            self.set_trace_callback(record)

def traced_connect(*args, **kwargs):
    kwargs['factory'] = TracedConnection
    return _original_connect(*args, **kwargs)

sqlite3.connect = traced_connect
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import shutil
import sqlite3
import subprocess
import tempfile

SCRIPT_PATH = '/home/user/audit_extract.py'
CSV_PATH = '/home/user/flagged_employees.csv'
DB_PATH = '/home/user/audit.db'
INSTRUMENT_PATH = '/tmp/audit_instrument'


def run_script(trace_path):
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    if os.path.exists(trace_path):
        os.remove(trace_path)

    env = os.environ.copy()
    env['PYTHONPATH'] = INSTRUMENT_PATH
    env['AUDIT_SQL_TRACE'] = trace_path
    result = subprocess.run(
        ['python3', SCRIPT_PATH], capture_output=True, text=True, env=env
    )
    assert result.returncode == 0, f"Script failed to run. Stderr: {result.stderr}"
    assert os.path.exists(CSV_PATH), f"CSV file {CSV_PATH} was not created by the script."

    with open(CSV_PATH, 'r', encoding='utf-8', newline='') as f:
        rows = list(csv.reader(f))

    statements = []
    if os.path.exists(trace_path):
        with open(trace_path, 'r', encoding='utf-8') as f:
            statements = [json.loads(line) for line in f if line.strip()]
    return rows, statements


def validate_single_aggregate_query(statements, expected_data, database_path):
    queries = [s for s in statements if re.search(r'\bSELECT\b', s, re.IGNORECASE)]
    assert len(queries) == 1, f"Expected exactly one SQL retrieval query, got: {statements}"
    query = queries[0]

    assert len(re.findall(r'\bJOIN\b', query, re.IGNORECASE)) >= 2, \
        f"Query must join employees, access logs, and records: {query}"
    for required in (r'\bGROUP\s+BY\b', r'\bHAVING\b', r'\bCOUNT\s*\(', r'\bORDER\s+BY\b'):
        assert re.search(required, query, re.IGNORECASE), \
            f"Executed query is missing required SQL aggregation/ordering construct {required}: {query}"

    # Execute the exact statement observed at runtime independently. This proves
    # the single joined aggregate query itself computes the required rows.
    conn = sqlite3.connect(database_path)
    try:
        actual = [[str(value) for value in row] for row in conn.execute(query).fetchall()]
    finally:
        conn.close()
    assert actual == expected_data, \
        f"The executed SQL query itself returned {actual}, expected {expected_data}"


def test_extract_script_exists_and_runs():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is not a regular file."

    rows, statements = run_script('/tmp/base_sql_trace.jsonl')

    assert len(rows) > 0, "CSV file is empty."
    assert rows[0] == ['emp_id', 'emp_name', 'access_count'], f"CSV header is incorrect. Got: {rows[0]}"

    expected_data = [
        ['3', 'Charlie', '4'],
        ['1', 'Alice', '3'],
        ['5', 'Eve', '3']
    ]

    assert rows[1:] == expected_data, f"CSV data does not match expected output. Got {rows[1:]}"
    validate_single_aggregate_query(statements, expected_data, DB_PATH)


def build_challenge_database(path):
    rng = random.SystemRandom()
    emp_ids = rng.sample(range(100, 1000), 6)
    outside_counts = [5, 3, 2, 4, 0, 6]
    employees = [
        (emp_id, f'Employee_{rng.randrange(10**8, 10**9)}')
        for emp_id in emp_ids
    ]

    records = [(501, 'CRITICAL'), (502, 'CRITICAL'), (503, 'LOW')]
    logs = []
    log_id = 1
    outside_times = ['07:59:59', '18:00:01', '00:15:00', '23:45:00', '06:30:00', '21:10:00']

    for index, ((emp_id, _), outside_count) in enumerate(zip(employees, outside_counts)):
        for occurrence in range(outside_count):
            logs.append((log_id, emp_id, 501 + occurrence % 2,
                         f'2025-02-{occurrence + 1:02d} {outside_times[occurrence]}'))
            log_id += 1

        # These critical accesses are inside hours, including both exact boundaries.
        for time_value in ('08:00:00', '12:30:00', '18:00:00'):
            logs.append((log_id, emp_id, 501, f'2025-03-{index + 1:02d} {time_value}'))
            log_id += 1

        # These are outside hours but non-critical and therefore must not count.
        for time_value in ('01:00:00', '22:00:00'):
            logs.append((log_id, emp_id, 503, f'2025-04-{index + 1:02d} {time_value}'))
            log_id += 1

    rng.shuffle(logs)
    conn = sqlite3.connect(path)
    try:
        conn.executescript('''
            CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, emp_name TEXT);
            CREATE TABLE records (record_id INTEGER PRIMARY KEY, sensitivity_level TEXT);
            CREATE TABLE access_logs (
                log_id INTEGER PRIMARY KEY,
                emp_id INTEGER,
                record_id INTEGER,
                access_time DATETIME
            );
        ''')
        conn.executemany('INSERT INTO employees VALUES (?, ?)', employees)
        conn.executemany('INSERT INTO records VALUES (?, ?)', records)
        conn.executemany('INSERT INTO access_logs VALUES (?, ?, ?, ?)', logs)
        conn.commit()
    finally:
        conn.close()

    name_by_id = dict(employees)
    qualifying = [
        [str(emp_id), name_by_id[emp_id], str(count)]
        for emp_id, count in zip(emp_ids, outside_counts)
        if count > 2
    ]
    qualifying.sort(key=lambda row: (-int(row[2]), int(row[0])))
    return qualifying


def test_against_unseen_database():
    with tempfile.TemporaryDirectory() as tmpdir:
        backup = os.path.join(tmpdir, 'original.db')
        pristine_challenge = os.path.join(tmpdir, 'pristine_challenge.db')
        shutil.copy2(DB_PATH, backup)
        try:
            os.remove(DB_PATH)
            expected_data = build_challenge_database(DB_PATH)
            shutil.copy2(DB_PATH, pristine_challenge)

            rows, statements = run_script('/tmp/challenge_sql_trace.jsonl')
            assert rows and rows[0] == ['emp_id', 'emp_name', 'access_count'], \
                f"CSV header is incorrect. Got: {rows[0] if rows else rows}"
            assert rows[1:] == expected_data, \
                f"CSV data does not match unseen database. Got {rows[1:]}, expected {expected_data}"
            validate_single_aggregate_query(statements, expected_data, pristine_challenge)
        finally:
            shutil.copy2(backup, DB_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
