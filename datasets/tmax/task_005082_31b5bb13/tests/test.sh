#!/bin/bash
set -e
mkdir -p /logs/verifier
mkdir -p /tmp/verifier_hook

cat << 'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import json
import os
import sqlite3

_trace_file = os.environ.get('SQLITE_TRACE_FILE')
_real_connect = sqlite3.connect

def _log(record):
    if _trace_file:
        with open(_trace_file, 'a', encoding='utf-8') as f:
            f.write(json.dumps(record) + '\n')

def _log_sql(kind, sql, has_parameters=False):
    _log({'kind': kind, 'sql': str(sql), 'has_parameters': bool(has_parameters)})

class LoggingCursor(sqlite3.Cursor):
    def execute(self, sql, *args, **kwargs):
        _log_sql('execute', sql, bool(args) or bool(kwargs))
        return super().execute(sql, *args, **kwargs)

    def executemany(self, sql, *args, **kwargs):
        _log_sql('executemany', sql, bool(args) or bool(kwargs))
        return super().executemany(sql, *args, **kwargs)

    def executescript(self, sql_script):
        _log_sql('executescript', sql_script, False)
        return super().executescript(sql_script)

class LoggingConnection(sqlite3.Connection):
    def cursor(self, *args, **kwargs):
        kwargs.setdefault('factory', LoggingCursor)
        return super().cursor(*args, **kwargs)

    def execute(self, sql, *args, **kwargs):
        _log_sql('execute', sql, bool(args) or bool(kwargs))
        return super().execute(sql, *args, **kwargs)

    def executemany(self, sql, *args, **kwargs):
        _log_sql('executemany', sql, bool(args) or bool(kwargs))
        return super().executemany(sql, *args, **kwargs)

    def executescript(self, sql_script):
        _log_sql('executescript', sql_script, False)
        return super().executescript(sql_script)

def connect(*args, **kwargs):
    database = args[0] if args else kwargs.get('database')
    _log({'kind': 'connect', 'database': database})
    kwargs.setdefault('factory', LoggingConnection)
    return _real_connect(*args, **kwargs)

sqlite3.connect = connect
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import subprocess
import sys
import uuid
import pytest

OUTPUT_FILE = '/home/user/output.csv'
SCRIPT_FILE = '/home/user/process_data.py'
DATA_FILE = '/home/user/data/transactions.csv'
HOOK_DIR = '/tmp/verifier_hook'
HEADER = ['id', 'timestamp', 'category', 'price', 'user_id']
ORIGINAL_ARGS = ['--category', 'electronics', '--min_price', '150.0', '--page', '2', '--page_size', '2']


def run_script(arguments, trace_name):
    trace_file = f'/tmp/{trace_name}.jsonl'
    if os.path.exists(trace_file):
        os.remove(trace_file)
    env = os.environ.copy()
    env['PYTHONPATH'] = HOOK_DIR + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    env['SQLITE_TRACE_FILE'] = trace_file
    result = subprocess.run(
        [sys.executable, SCRIPT_FILE] + arguments,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        env=env,
    )
    assert result.returncode == 0, f'Script failed for {arguments}: stdout={result.stdout!r}, stderr={result.stderr!r}'
    assert os.path.isfile(OUTPUT_FILE), f'The output file {OUTPUT_FILE} was not created.'
    records = []
    if os.path.isfile(trace_file):
        with open(trace_file, encoding='utf-8') as f:
            records = [json.loads(line) for line in f if line.strip()]
    return records


def assert_database_operations(records):
    assert any(r.get('kind') == 'connect' and r.get('database') == ':memory:' for r in records), \
        "The script must connect to an in-memory SQLite database using sqlite3.connect(':memory:')."

    sql_records = [r for r in records if r.get('kind') in {'execute', 'executemany', 'executescript'}]
    combined_sql = '\n'.join(r.get('sql', '') for r in sql_records)
    normalized = re.sub(r'\s+', ' ', combined_sql.lower())

    assert re.search(r'create\s+table(?:\s+if\s+not\s+exists)?\s+transactions\b', normalized), \
        "The script must create the transactions table."
    for column, datatype in [('id', 'integer'), ('timestamp', 'text'), ('category', 'text'), ('price', 'real'), ('user_id', 'integer')]:
        assert re.search(rf'\b{column}\s+{datatype}\b', normalized), \
            f'The transactions table must define {column} as {datatype.upper()}.'
    assert re.search(r'create\s+(?:unique\s+)?index(?:\s+if\s+not\s+exists)?\s+idx_category_price\s+on\s+transactions\s*\(\s*category\s*,\s*price\s*\)', normalized), \
        "The script must create idx_category_price on (category, price)."

    parameterized_selects = [
        r for r in sql_records
        if re.search(r'\bselect\b', r.get('sql', ''), re.I)
        and r.get('has_parameters')
        and ('?' in r.get('sql', '') or re.search(r':\w+', r.get('sql', '')))
    ]
    assert parameterized_selects, 'The SELECT query must be executed with bound parameters.'


def read_output():
    with open(OUTPUT_FILE, 'r', newline='') as f:
        return list(csv.reader(f))


def test_output_csv_exists_and_correct():
    records = run_script(ORIGINAL_ARGS, 'original_trace')
    assert_database_operations(records)
    assert os.path.isfile(OUTPUT_FILE), f"The output file {OUTPUT_FILE} was not created."

    rows = read_output()
    expected_rows = [
        ['id', 'timestamp', 'category', 'price', 'user_id'],
        ['10', '2023-01-01T10:45:00', 'electronics', '399.99', '110'],
        ['1', '2023-01-01T10:00:00', 'electronics', '299.99', '101']
    ]
    assert rows == expected_rows, f"The contents of {OUTPUT_FILE} do not match the expected output for the given arguments. Expected {expected_rows}, got {rows}."


def test_script_exists_and_contains_requirements():
    assert os.path.isfile(SCRIPT_FILE), f"The script file {SCRIPT_FILE} was not created."

    with open(SCRIPT_FILE, 'r') as f:
        content = f.read()

    assert "idx_category_price" in content, "The script must create a composite index named 'idx_category_price'."
    has_qmark = "?" in content
    has_named = re.search(r':\w+', content)
    assert has_qmark or has_named, "The script must use parameterized SQL queries (e.g., using '?' or named parameters)."
    assert "argparse" in content, "The script must use the 'argparse' module."
    assert "sqlite3" in content, "The script must use the 'sqlite3' module."


def expected_for(rows, category, minimum, page, page_size):
    selected = [r for r in rows if r[2] == category and float(r[3]) >= minimum]
    selected.sort(key=lambda r: (-float(r[3]), int(r[0])))
    start = (page - 1) * page_size
    selected = selected[start:start + page_size]
    return [HEADER] + [[str(int(r[0])), r[1], r[2], str(float(r[3])), str(int(r[4]))] for r in selected]


def test_dynamic_inputs_and_pagination():
    with open(DATA_FILE, 'rb') as f:
        original_data = f.read()

    token = uuid.uuid4().hex
    target = 'category_' + token
    hostile = "quote_'_" + token
    rows = [
        ['41', '2025-04-01T10:00:00', target, '275.25', '901'],
        ['7', '2025-04-01T10:01:00', target, '410.75', '902'],
        ['19', '2025-04-01T10:02:00', target, '275.25', '903'],
        ['3', '2025-04-01T10:03:00', target, '99.50', '904'],
        ['88', '2025-04-01T10:04:00', target, '600.10', '905'],
        ['25', '2025-04-01T10:05:00', target, '180.40', '906'],
        ['12', '2025-04-01T10:06:00', target + '_other', '999.90', '907'],
        ['52', '2025-04-01T10:07:00', hostile, '333.30', '908'],
        ['53', '2025-04-01T10:08:00', hostile, '133.30', '909'],
    ]

    try:
        with open(DATA_FILE, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(HEADER)
            writer.writerows(rows)

        cases = [
            (target, 150.0, 1, 3),
            (target, 150.0, 2, 2),
            (hostile, 0.0, 1, 10),
            ('missing_' + token, 0.0, 1, 4),
        ]
        for number, (category, minimum, page, page_size) in enumerate(cases):
            arguments = [
                '--category', category,
                '--min_price', str(minimum),
                '--page', str(page),
                '--page_size', str(page_size),
            ]
            records = run_script(arguments, f'dynamic_trace_{number}_{token}')
            assert_database_operations(records)
            expected = expected_for(rows, category, minimum, page, page_size)
            actual = read_output()
            assert actual == expected, f'Incorrect output for {arguments}. Expected {expected}, got {actual}.'
    finally:
        with open(DATA_FILE, 'wb') as f:
            f.write(original_data)
        subprocess.run([sys.executable, SCRIPT_FILE] + ORIGINAL_ARGS, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
