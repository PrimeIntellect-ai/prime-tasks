#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import os
import secrets
import sqlite3
import subprocess
from datetime import datetime

DB_PATH = '/home/user/backups.db'
CSV_PATH = '/home/user/anomalies.csv'
LOG_PATH = '/home/user/backup_logs.jsonl'


def test_database_exists_and_schema():
    """Test that the SQLite database and required table exist."""
    assert os.path.isfile(DB_PATH), f"Database file missing at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='backup_history';")
    table = cursor.fetchone()
    conn.close()

    assert table is not None, "Table 'backup_history' does not exist in the database."


def test_database_content():
    """Test that the database contains only the valid rows."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    cursor.execute("SELECT backup_id, timestamp, status, size_bytes, database_name FROM backup_history ORDER BY backup_id")
    rows = cursor.fetchall()
    conn.close()

    assert len(rows) == 12, f"Expected exactly 12 valid rows in backup_history, found {len(rows)}."

    backup_ids = {row['backup_id'] for row in rows}
    assert 'b_inv' not in backup_ids, "Invalid row 'b_inv' (string size_bytes) was not filtered out."

    # Check a sample valid row
    b1 = next((r for r in rows if r['backup_id'] == 'b1'), None)
    assert b1 is not None, "Missing backup_id 'b1'"
    assert b1['size_bytes'] == 100
    assert b1['status'] == 'SUCCESS'
    assert b1['database_name'] == 'DB_ALPHA'


def test_csv_exists_and_content():
    """Test that the anomalies CSV is generated correctly."""
    assert os.path.isfile(CSV_PATH), f"CSV file missing at {CSV_PATH}"

    with open(CSV_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "CSV file is empty."

    header = rows[0]
    expected_header = ['database_name', 'backup_id', 'spike_size']
    assert header == expected_header, f"CSV header mismatch. Expected {expected_header}, got {header}."

    data_rows = rows[1:]
    assert len(data_rows) == 2, f"Expected 2 anomaly rows, found {len(data_rows)}."

    # Check sorting
    db_names = [r[0] for r in data_rows]
    assert db_names == sorted(db_names), "CSV rows are not sorted alphabetically by database_name."

    # Check specific values
    expected_data = [
        ['DB_ALPHA', 'b4', '392.5'],
        ['DB_BETA', 'b9', '12.5']
    ]

    assert data_rows == expected_data, f"CSV data mismatch. Expected {expected_data}, got {data_rows}."


def _candidate_scripts():
    candidates = []
    seen = set()
    roots = ['/home/user', '/root', '/workspace', '/tmp']
    for root in roots:
        if not os.path.isdir(root):
            continue
        for path in glob.glob(os.path.join(root, '**', '*'), recursive=True):
            if path in seen or not os.path.isfile(path):
                continue
            seen.add(path)
            if path == '/tmp/test_final_state.py' or '/site-packages/' in path or '/__pycache__/' in path:
                continue
            try:
                if os.path.getsize(path) > 1024 * 1024:
                    continue
                with open(path, 'rb') as f:
                    source = f.read()
            except OSError:
                continue
            is_python = path.endswith('.py') or source.startswith(b'#!/usr/bin/env python') or source.startswith(b'#!/usr/bin/python')
            if not is_python:
                continue
            # A pipeline for the fixed paths must identify all three artifacts.
            if all(name in source for name in (b'backup_logs.jsonl', b'backups.db', b'anomalies.csv')):
                candidates.append(path)
    return sorted(candidates)


def _write_dynamic_fixture():
    token = secrets.token_hex(6)
    offset = secrets.randbelow(700) + 50
    db_a = f'A_{token}'
    db_b = f'B_{token}'
    db_c = f'C_{token}'

    def row(suffix, ts, status, size, database):
        return {
            'backup_id': f'{token}_{suffix}',
            'timestamp': ts,
            'status': status,
            'size_bytes': size,
            'database_name': database,
        }

    valid = [
        row('a4', '2025-03-04T01:00:00Z', 'SUCCESS', offset + 500, db_a),
        row('a1', '2025-03-01T01:00:00Z', 'SUCCESS', offset + 100, db_a),
        row('af', '2025-03-02T12:00:00Z', 'FAILURE', offset + 9000, db_a),
        row('a3', '2025-03-03T01:00:00Z', 'SUCCESS', offset + 111, db_a),
        row('a2', '2025-03-02T01:00:00Z', 'SUCCESS', offset + 120, db_a),
        row('b3', '2025-04-03T02:00:00Z', 'SUCCESS', offset + 190, db_b),
        row('b1', '2025-04-01T02:00:00Z', 'SUCCESS', offset + 200, db_b),
        row('b4', '2025-04-04T02:00:00Z', 'SUCCESS', offset + 225, db_b),
        row('b2', '2025-04-02T02:00:00Z', 'SUCCESS', offset + 180, db_b),
        row('c1', '2025-05-01T03:00:00Z', 'SUCCESS', offset + 100, db_c),
        row('c2', '2025-05-02T03:00:00Z', 'SUCCESS', offset + 100, db_c),
        row('c3', '2025-05-03T03:00:00Z', 'SUCCESS', offset + 90, db_c),
        row('c4', '2025-05-04T03:00:00Z', 'SUCCESS', offset + 80, db_c),
    ]

    invalid = [
        {**valid[0], 'backup_id': f'{token}_extra', 'extra': 'reject'},
        {k: v for k, v in valid[1].items() if k != 'status'},
        {**valid[2], 'backup_id': f'{token}_badsize', 'size_bytes': str(offset)},
        {**valid[3], 'backup_id': f'{token}_boolsize', 'size_bytes': True},
        {**valid[4], 'backup_id': f'{token}_badstatus', 'status': 'success'},
        {**valid[5], 'backup_id': f'{token}_badtime', 'timestamp': 'not-an-iso-timestamp'},
        {**valid[6], 'backup_id': 12345},
    ]

    mixed = valid[:4] + invalid[:3] + valid[4:9] + invalid[3:] + valid[9:]
    with open(LOG_PATH, 'w', encoding='utf-8') as f:
        for item in mixed[:8]:
            f.write(json.dumps(item) + '\n')
        f.write('{malformed json\n')
        for item in mixed[8:]:
            f.write(json.dumps(item) + '\n')
    return valid


def _expected_anomalies(valid):
    by_db = {}
    for item in valid:
        if item['status'] == 'SUCCESS':
            by_db.setdefault(item['database_name'], []).append(item)

    result = []
    for database, items in by_db.items():
        items.sort(key=lambda x: x['timestamp'])
        candidates = []
        for index in range(2, len(items)):
            expected = (items[index - 2]['size_bytes'] + items[index - 1]['size_bytes']) / 2.0
            candidates.append((items[index]['size_bytes'] - expected, items[index]['backup_id']))
        if candidates:
            spike, backup_id = max(candidates, key=lambda x: x[0])
            if spike > 0:
                result.append([database, backup_id, f'{spike:.1f}'])
    return sorted(result, key=lambda x: x[0])


def _validate_dynamic_outputs(valid):
    if not os.path.isfile(DB_PATH) or not os.path.isfile(CSV_PATH):
        return False, 'missing database or CSV'
    try:
        conn = sqlite3.connect(DB_PATH)
        rows = conn.execute(
            "SELECT backup_id, timestamp, status, size_bytes, database_name, typeof(size_bytes) "
            "FROM backup_history"
        ).fetchall()
        conn.close()
    except Exception as exc:
        return False, f'database error: {exc}'

    actual = sorted(rows)
    expected = sorted((
        r['backup_id'], r['timestamp'], r['status'], r['size_bytes'], r['database_name'], 'integer'
    ) for r in valid)
    if actual != expected:
        return False, f'database rows differ: expected {expected!r}, got {actual!r}'

    try:
        with open(CSV_PATH, newline='', encoding='utf-8') as f:
            csv_rows = list(csv.reader(f))
    except Exception as exc:
        return False, f'CSV error: {exc}'

    expected_csv = [['database_name', 'backup_id', 'spike_size']] + _expected_anomalies(valid)
    if csv_rows != expected_csv:
        return False, f'CSV differs: expected {expected_csv!r}, got {csv_rows!r}'
    return True, ''


def test_pipeline_script_executes_on_unseen_input():
    scripts = _candidate_scripts()
    assert scripts, 'No Python implementation script for the requested pipeline was found.'

    failures = []
    for script in scripts:
        valid = _write_dynamic_fixture()
        for artifact in (DB_PATH, CSV_PATH):
            try:
                os.remove(artifact)
            except FileNotFoundError:
                pass
        try:
            completed = subprocess.run(
                ['python3', script],
                cwd=os.path.dirname(script) or '/home/user',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
        except Exception as exc:
            failures.append(f'{script}: execution failed: {exc}')
            continue
        if completed.returncode != 0:
            failures.append(f'{script}: exited {completed.returncode}: {completed.stderr[-500:]}')
            continue
        ok, reason = _validate_dynamic_outputs(valid)
        if ok:
            return
        failures.append(f'{script}: {reason}')

    raise AssertionError('No implementation script correctly processed unseen input. ' + ' | '.join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
