#!/bin/bash
set -e
mkdir -p /logs/verifier

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
from collections import Counter

import pytest

DB_PATH = '/home/user/sensor_data.db'
JSON_PATH = '/home/user/quarantine.json'
SCRIPT_PATH = '/home/user/process_data.py'
RAW_PATH = '/home/user/raw_data'
FIELDS = ['sensor_id', 'timestamp', 'temperature', 'humidity', 'status']


def test_database_exists():
    assert os.path.exists(DB_PATH), f'Database file {DB_PATH} not found.'
    assert os.path.isfile(DB_PATH), f'{DB_PATH} is not a file.'


def test_database_schema_and_content():
    assert os.path.exists(DB_PATH), 'Database missing'
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='readings'")
    assert c.fetchone() is not None, "Table 'readings' does not exist in the database."

    c.execute('PRAGMA table_info(readings)')
    columns = {row[1]: row[2].upper() for row in c.fetchall()}
    expected_columns = {
        'sensor_id': 'TEXT',
        'timestamp': 'TEXT',
        'temperature': 'REAL',
        'humidity': 'REAL',
        'status': 'TEXT'
    }
    for col, ctype in expected_columns.items():
        assert col in columns, f"Column '{col}' missing from readings table."

    c.execute('SELECT count(*) FROM readings')
    db_count = c.fetchone()[0]
    assert db_count == 3, f'Expected exactly 3 valid rows in the database, got {db_count}.'

    c.execute('SELECT sensor_id, timestamp, temperature, humidity, status FROM readings ORDER BY timestamp')
    rows = c.fetchall()
    expected_rows = [
        ('SN-1234', '2023-10-01T10:00:00Z', 22.5, 45.0, 'ACTIVE'),
        ('SN-0001', '2023-10-01T10:20:00Z', 0.0, 0.0, 'OFFLINE'),
        ('SN-5555', '2023-10-02T10:10:00Z', 85.0, 100.0, 'MAINTENANCE')
    ]
    for expected, actual in zip(expected_rows, rows):
        assert actual == expected, f'Expected row {expected}, got {actual}.'
    conn.close()


def test_quarantine_json_exists():
    assert os.path.exists(JSON_PATH), f'Quarantine JSON file {JSON_PATH} not found.'
    assert os.path.isfile(JSON_PATH), f'{JSON_PATH} is not a file.'


def test_quarantine_json_content():
    assert os.path.exists(JSON_PATH), 'JSON missing'
    with open(JSON_PATH, 'r') as f:
        try:
            q_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {JSON_PATH} is not valid JSON.')

    assert isinstance(q_data, list), 'Quarantine JSON should contain a single JSON array.'
    assert len(q_data) == 5, f'Expected exactly 5 invalid rows in JSON, got {len(q_data)}.'

    for row in q_data:
        assert 'invalid_columns' in row, "Each object must contain an 'invalid_columns' key."
        cols = row['invalid_columns']
        assert isinstance(cols, list), "'invalid_columns' must be a list of strings."
        assert cols == sorted(cols), f"'invalid_columns' must be sorted alphabetically. Got: {cols}"
        if row.get('temperature') == '100.0':
            assert cols == ['temperature'], f"Expected ['temperature'] for row with temp 100.0, got {cols}"
        elif row.get('sensor_id') == 'S-123':
            assert cols == ['sensor_id', 'status'], f"Expected ['sensor_id', 'status'] for S-123, got {cols}"
        elif row.get('temperature') == '-45.0':
            assert cols == ['humidity', 'temperature'], f"Expected ['humidity', 'temperature'] for temp -45.0, got {cols}"
        elif row.get('temperature') == 'abc':
            assert cols == ['temperature'], f"Expected ['temperature'] for temp 'abc', got {cols}"
        elif row.get('timestamp') == '2023-10-02 10:05:00Z':
            assert cols == ['timestamp'], f"Expected ['timestamp'] for invalid timestamp format, got {cols}"
        else:
            pytest.fail(f'Unexpected row found in quarantine JSON: {row}')

    expected = [
        {'sensor_id': 'SN-1234', 'timestamp': '2023-10-01T10:05:00Z', 'temperature': '100.0', 'humidity': '45.0', 'status': 'ACTIVE', 'invalid_columns': ['temperature']},
        {'sensor_id': 'S-123', 'timestamp': '2023-10-01T10:10:00Z', 'temperature': '22.5', 'humidity': '45.0', 'status': 'BROKEN', 'invalid_columns': ['sensor_id', 'status']},
        {'sensor_id': 'SN-9999', 'timestamp': '2023-10-01T10:15:00Z', 'temperature': '-45.0', 'humidity': '105.0', 'status': 'MAINTENANCE', 'invalid_columns': ['humidity', 'temperature']},
        {'sensor_id': 'SN-4321', 'timestamp': '2023-10-02T10:00:00Z', 'temperature': 'abc', 'humidity': '45.0', 'status': 'ACTIVE', 'invalid_columns': ['temperature']},
        {'sensor_id': 'SN-4321', 'timestamp': '2023-10-02 10:05:00Z', 'temperature': '20.0', 'humidity': '45.0', 'status': 'ACTIVE', 'invalid_columns': ['timestamp']}
    ]
    canonical = lambda obj: json.dumps(obj, sort_keys=True)
    assert sorted(map(canonical, q_data)) == sorted(map(canonical, expected)), \
        'Quarantine objects must contain every original CSV key-value pair and the correct invalid_columns.'


def validate(row):
    invalid = []
    if re.fullmatch(r'SN-\d{4}', row['sensor_id']) is None:
        invalid.append('sensor_id')
    if re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z', row['timestamp']) is None:
        invalid.append('timestamp')
    try:
        temperature = float(row['temperature'])
        if not -40.0 <= temperature <= 85.0:
            invalid.append('temperature')
    except (TypeError, ValueError):
        invalid.append('temperature')
    try:
        humidity = float(row['humidity'])
        if not 0.0 <= humidity <= 100.0:
            invalid.append('humidity')
    except (TypeError, ValueError):
        invalid.append('humidity')
    if row['status'] not in {'ACTIVE', 'MAINTENANCE', 'OFFLINE'}:
        invalid.append('status')
    return sorted(invalid)


def remove_path(path):
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    elif os.path.lexists(path):
        os.remove(path)


def test_script_executes_pipeline_on_fresh_unseen_inputs_and_appends():
    assert os.path.exists(SCRIPT_PATH), f'Script {SCRIPT_PATH} not found.'
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} is not a file.'

    backup = tempfile.mkdtemp(prefix='pipeline-backup-', dir='/tmp')
    saved = {}
    for path in (RAW_PATH, DB_PATH, JSON_PATH):
        if os.path.lexists(path):
            destination = os.path.join(backup, os.path.basename(path))
            shutil.move(path, destination)
            saved[path] = destination

    try:
        os.makedirs(RAW_PATH)
        ids = random.sample(range(1000, 10000), 8)
        rows_a = [
            [f'SN-{ids[0]:04d}', '2041-03-04T05:06:07Z', '-40.0', '0.0', 'ACTIVE'],
            [f'BAD-{ids[1]}', '2041-03-04T05:07:07Z', '12.25', '55.5', 'OFFLINE'],
            [f'SN-{ids[2]:04d}', '2041-03-04T05:08:07Z', '85.01', '44.0', 'MAINTENANCE'],
            [f'SN-{ids[3]:04d}', '2041-03-04T05:09:07Z', '21.0', 'not-a-number', 'ACTIVE']
        ]
        rows_b = [
            [f'SN-{ids[4]:04d}', '2042-11-12T13:14:15Z', '85.0', '100.0', 'MAINTENANCE'],
            [f'SN-{ids[5]:04d}', '2042-11-12 13:15:15Z', '1.5', '2.5', 'OFFLINE'],
            [f'SN-{ids[6]:04d}', '2042-11-12T13:16:15Z', 'abc', '50.0', 'ACTIVE'],
            [f'SN-{ids[7]:04d}', '2042-11-12T13:17:15Z', '-40.01', '100.01', 'BROKEN']
        ]
        for filename, rows in [('unseen_a.csv', rows_a), ('unseen_b.csv', rows_b)]:
            with open(os.path.join(RAW_PATH, filename), 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(FIELDS)
                writer.writerows(rows)
        with open(os.path.join(RAW_PATH, 'ignore.txt'), 'w') as f:
            f.write('not csv')

        sentinel = ('SN-0000', '2030-01-01T00:00:00Z', 10.0, 20.0, 'ACTIVE')
        conn = sqlite3.connect(DB_PATH)
        conn.execute('CREATE TABLE readings (sensor_id TEXT, timestamp TEXT, temperature REAL, humidity REAL, status TEXT)')
        conn.execute('INSERT INTO readings VALUES (?, ?, ?, ?, ?)', sentinel)
        conn.commit()
        conn.close()

        completed = subprocess.run(
            ['python3', SCRIPT_PATH], cwd='/home/user', text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert completed.returncode == 0, \
            f'process_data.py failed on fresh inputs. stdout={completed.stdout!r} stderr={completed.stderr!r}'

        source_rows = [dict(zip(FIELDS, row)) for row in rows_a + rows_b]
        expected_valid = [row for row in source_rows if not validate(row)]
        expected_invalid = []
        for row in source_rows:
            failures = validate(row)
            if failures:
                expected_invalid.append({**row, 'invalid_columns': failures})

        conn = sqlite3.connect(DB_PATH)
        actual_db = conn.execute(
            'SELECT sensor_id, timestamp, temperature, humidity, status FROM readings'
        ).fetchall()
        conn.close()
        expected_db = [sentinel] + [
            (row['sensor_id'], row['timestamp'], float(row['temperature']),
             float(row['humidity']), row['status'])
            for row in expected_valid
        ]
        assert Counter(actual_db) == Counter(expected_db), \
            'The script did not append exactly the valid rows to the pre-existing table.'

        assert os.path.isfile(JSON_PATH), 'The script did not create quarantine.json.'
        with open(JSON_PATH) as f:
            actual_invalid = json.load(f)
        assert isinstance(actual_invalid, list), 'quarantine.json must contain one JSON array.'
        canonical = lambda obj: json.dumps(obj, sort_keys=True)
        assert Counter(map(canonical, actual_invalid)) == Counter(map(canonical, expected_invalid)), \
            'The script must quarantine every invalid row with all original values and derived invalid_columns.'
    finally:
        for path in (RAW_PATH, DB_PATH, JSON_PATH):
            remove_path(path)
        for path, stored in saved.items():
            shutil.move(stored, path)
        shutil.rmtree(backup, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
