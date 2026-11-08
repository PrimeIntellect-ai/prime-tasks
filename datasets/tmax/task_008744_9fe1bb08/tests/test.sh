#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import runpy
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

DB_PATH = Path('/home/user/transactions.db')
OUTPUT_PATH = Path('/home/user/flagged_anomalies.json')
REQUIRED_KEYS = {
    'transaction_id', 'user_id', 'timestamp', 'amount', 'moving_average'
}


def get_expected_anomalies():
    """Compute expected anomalies directly from the database to align with the truth."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute(
        'SELECT id, user_id, timestamp, amount '
        'FROM transactions ORDER BY user_id, timestamp ASC'
    )
    rows = cursor.fetchall()
    conn.close()

    users = {}
    for row in rows:
        users.setdefault(row['user_id'], []).append(row)

    anomalies = []
    for user_id, transactions in users.items():
        for i in range(4, len(transactions)):
            window = transactions[i-4:i+1]
            avg = sum(t['amount'] for t in window) / 5.0
            current_tx = transactions[i]
            if current_tx['amount'] > 2.0 * avg:
                anomalies.append({
                    'transaction_id': current_tx['id'],
                    'user_id': current_tx['user_id'],
                    'timestamp': current_tx['timestamp'],
                    'amount': float(current_tx['amount']),
                    'moving_average': round(avg, 2),
                })
    return anomalies


def candidate_scripts():
    roots = [Path('/home/user'), Path('/workspace'), Path('/tmp'), Path('/root')]
    this_file = Path(__file__).resolve()
    found = []
    for root in roots:
        if not root.exists():
            continue
        for path in root.rglob('*.py'):
            try:
                resolved = path.resolve()
                if resolved == this_file or '/tests/' in str(resolved):
                    continue
                source = path.read_text(errors='replace')
            except (OSError, UnicodeError):
                continue
            lower = source.lower()
            if ('transactions.db' in lower and
                    'flagged_anomalies.json' in lower and
                    'sqlite' in lower):
                found.append((path, source))
    return found


def has_validation_code(source):
    lower = source.lower()
    if not all(name in source for name in REQUIRED_KEYS):
        return False
    library_validation = 'pydantic' in lower or 'jsonschema' in lower
    custom_validation = (
        ('isinstance' in lower or 'type(' in lower) and
        ('raise ' in lower or 'assert ' in lower)
    )
    return library_validation or custom_validation


def run_pipeline(path, trace_path):
    wrapper = r'''
import os
import runpy
import sqlite3

real_connect = sqlite3.connect
trace_path = os.environ['PIPELINE_SQL_TRACE']
script_path = os.environ['PIPELINE_SCRIPT']

def traced_connect(*args, **kwargs):
    conn = real_connect(*args, **kwargs)
    def record(statement):
        with open(trace_path, 'a', encoding='utf-8') as f:
            f.write(statement.replace('\\n', ' ') + '\\n--STATEMENT--\\n')
    conn.set_trace_callback(record)
    return conn

sqlite3.connect = traced_connect
runpy.run_path(script_path, run_name='__main__')
'''
    env = os.environ.copy()
    env['PIPELINE_SCRIPT'] = str(path)
    env['PIPELINE_SQL_TRACE'] = str(trace_path)
    return subprocess.run(
        [sys.executable, '-c', wrapper],
        cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30,
    )


def trace_uses_required_window(trace_path):
    if not trace_path.is_file():
        return False
    statements = trace_path.read_text(errors='replace').split('--STATEMENT--')
    for statement in statements:
        sql = re.sub(r'\s+', ' ', statement).upper()
        has_avg_window = re.search(
            r'AVG\s*\([^)]*AMOUNT[^)]*\)\s*OVER(?:\s*\(|\s+[A-Z_][A-Z0-9_]*)', sql
        )
        has_partition = re.search(r'PARTITION\s+BY\s+(?:[A-Z_][A-Z0-9_]*\.)?USER_ID', sql)
        has_order = re.search(r'ORDER\s+BY\s+(?:[A-Z_][A-Z0-9_]*\.)?TIMESTAMP(?:\s+ASC)?', sql)
        exact_frame = (
            re.search(r'ROWS\s+BETWEEN\s+4\s+PRECEDING\s+AND\s+CURRENT\s+ROW', sql)
            or re.search(r'ROWS\s+4\s+PRECEDING', sql)
        )
        if has_avg_window and has_partition and has_order and exact_frame:
            return True
    return False


def inject_invalid_flagged_record():
    conn = sqlite3.connect(DB_PATH)
    next_id = conn.execute('SELECT COALESCE(MAX(id), 0) + 1 FROM transactions').fetchone()[0]
    rows = [
        (next_id + 0, None, 1900000001, 1.0),
        (next_id + 1, None, 1900000002, 1.0),
        (next_id + 2, None, 1900000003, 1.0),
        (next_id + 3, None, 1900000004, 1.0),
        (next_id + 4, None, 1900000005, 20.0),
    ]
    conn.executemany('INSERT INTO transactions VALUES (?, ?, ?, ?)', rows)
    conn.commit()
    conn.close()


def remove_output():
    try:
        OUTPUT_PATH.unlink()
    except FileNotFoundError:
        pass


@pytest.fixture(scope='session', autouse=True)
def execute_submitted_pipeline():
    candidates = candidate_scripts()
    assert candidates, 'No Python data-pipeline script was found.'

    fd, backup_name = tempfile.mkstemp(prefix='transactions-', suffix='.db')
    os.close(fd)
    backup = Path(backup_name)
    shutil.copy2(DB_PATH, backup)
    failures = []

    try:
        for script, source in candidates:
            if not has_validation_code(source):
                failures.append(f'{script}: no schema-validation implementation found')
                continue

            shutil.copy2(backup, DB_PATH)
            remove_output()
            trace = Path(tempfile.mktemp(prefix='sql-trace-'))
            try:
                result = run_pipeline(script, trace)
            except (subprocess.TimeoutExpired, OSError) as exc:
                failures.append(f'{script}: execution failed: {exc}')
                continue

            if result.returncode != 0 or not OUTPUT_PATH.is_file():
                failures.append(f'{script}: did not successfully create the output')
                trace.unlink(missing_ok=True)
                continue
            if not trace_uses_required_window(trace):
                failures.append(f'{script}: required SQLite AVG window query was not executed')
                trace.unlink(missing_ok=True)
                continue
            trace.unlink(missing_ok=True)

            # A strict validator must refuse an anomalous row whose user_id is NULL.
            shutil.copy2(backup, DB_PATH)
            inject_invalid_flagged_record()
            remove_output()
            invalid_trace = Path(tempfile.mktemp(prefix='invalid-sql-trace-'))
            try:
                invalid_result = run_pipeline(script, invalid_trace)
            except (subprocess.TimeoutExpired, OSError):
                invalid_result = None
            invalid_trace.unlink(missing_ok=True)
            rejected_invalid = (
                invalid_result is None or invalid_result.returncode != 0 or
                not OUTPUT_PATH.is_file()
            )
            if not rejected_invalid:
                failures.append(f'{script}: schema-invalid flagged record was not rejected')
                continue

            # Restore the real database and execute the accepted pipeline once more.
            shutil.copy2(backup, DB_PATH)
            remove_output()
            final_trace = Path(tempfile.mktemp(prefix='final-sql-trace-'))
            final_result = run_pipeline(script, final_trace)
            final_window_ok = trace_uses_required_window(final_trace)
            final_trace.unlink(missing_ok=True)
            if final_result.returncode == 0 and OUTPUT_PATH.is_file() and final_window_ok:
                return
            failures.append(f'{script}: final execution failed')

        shutil.copy2(backup, DB_PATH)
        pytest.fail('No valid executable pipeline found. ' + '; '.join(failures))
    finally:
        backup.unlink(missing_ok=True)


def test_json_file_exists():
    """Verify that the output JSON file exists."""
    assert OUTPUT_PATH.is_file(), f'Output file {OUTPUT_PATH} is missing.'


def test_json_format_and_schema():
    """Verify valid, pretty-printed JSON and the required strict schema."""
    raw = OUTPUT_PATH.read_text()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        pytest.fail(f'File {OUTPUT_PATH} does not contain valid JSON.')

    assert isinstance(data, list), 'The JSON root must be an array.'

    # Pretty printing requires a multiline array with indented property lines.
    lines = raw.splitlines()
    assert len(lines) > 2, 'The JSON output is not pretty-printed.'
    assert lines[0].strip() == '[' and lines[-1].strip() == ']', 'Expected a formatted JSON array.'
    property_lines = [line for line in lines if re.match(r'^\s+"[^"\n]+"\s*:', line)]
    assert len(property_lines) >= len(data) * len(REQUIRED_KEYS), 'JSON objects must be pretty-printed.'

    # Check lexical formatting, since json.loads discards trailing zeroes.
    moving_average_tokens = re.findall(
        r'"moving_average"\s*:\s*(-?(?:0|[1-9]\d*)\.\d{2})(?=\s*[,}])', raw
    )
    assert len(moving_average_tokens) == len(data), (
        "Every moving_average must be written as a JSON number with exactly two decimal places."
    )

    for i, item in enumerate(data):
        assert isinstance(item, dict), f'Item at index {i} is not a JSON object.'
        assert set(item) == REQUIRED_KEYS, f'Item at index {i} does not strictly match the schema.'
        assert type(item['transaction_id']) is int, f"Item at index {i} 'transaction_id' is not an integer."
        assert type(item['user_id']) is str, f"Item at index {i} 'user_id' is not a string."
        assert type(item['timestamp']) is int, f"Item at index {i} 'timestamp' is not an integer."
        assert type(item['amount']) is float, f"Item at index {i} 'amount' is not a float."
        assert type(item['moving_average']) is float, f"Item at index {i} 'moving_average' is not a float."


def test_anomalies_correctness():
    """Verify that the anomalies exactly match those derived from the database."""
    with OUTPUT_PATH.open() as f:
        data = json.load(f)

    expected = get_expected_anomalies()
    assert len(data) == len(expected), f'Expected {len(expected)} anomalies, but found {len(data)}.'

    data_sorted = sorted(data, key=lambda x: x['transaction_id'])
    expected_sorted = sorted(expected, key=lambda x: x['transaction_id'])
    for act, exp in zip(data_sorted, expected_sorted):
        assert act['transaction_id'] == exp['transaction_id'], f"Transaction ID mismatch: expected {exp['transaction_id']}, got {act['transaction_id']}."
        assert act['user_id'] == exp['user_id'], f"User ID mismatch for tx {exp['transaction_id']}."
        assert act['timestamp'] == exp['timestamp'], f"Timestamp mismatch for tx {exp['transaction_id']}."
        assert act['amount'] == exp['amount'], f"Amount mismatch for tx {exp['transaction_id']}."
        assert round(act['moving_average'], 2) == exp['moving_average'], f"Moving average mismatch for tx {exp['transaction_id']}: expected {exp['moving_average']}, got {act['moving_average']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
