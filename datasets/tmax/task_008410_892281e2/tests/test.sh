#!/bin/bash
set -u
mkdir -p /logs/verifier

TMPDIR=$(mktemp -d)
cp -a /home/user/sensor_data.db "$TMPDIR/sensor_data.db"
if [ -f /home/user/daily_summary.json ]; then
    cp -a /home/user/daily_summary.json "$TMPDIR/daily_summary.json"
    HAD_SUMMARY=1
else
    HAD_SUMMARY=0
fi

cleanup() {
    rm -f /home/user/sensor_data.db /home/user/sensor_data.db-wal /home/user/sensor_data.db-shm
    cp -a "$TMPDIR/sensor_data.db" /home/user/sensor_data.db
    rm -f /home/user/daily_summary.json
    if [ "$HAD_SUMMARY" -eq 1 ]; then
        cp -a "$TMPDIR/daily_summary.json" /home/user/daily_summary.json
    fi
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

SUMMARY_PATH = '/home/user/daily_summary.json'

def test_summary_file_exists():
    assert os.path.exists(SUMMARY_PATH), f"Expected output file {SUMMARY_PATH} does not exist."
    assert os.path.isfile(SUMMARY_PATH), f"Path {SUMMARY_PATH} is not a file."

def test_summary_json_validity():
    with open(SUMMARY_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {SUMMARY_PATH} does not contain valid JSON.")
    assert isinstance(data, list), f"Expected the JSON root to be a list, got {type(data).__name__}."

def test_summary_contents():
    with open(SUMMARY_PATH, 'r') as f:
        data = json.load(f)

    expected_data = [
        {"date": "2023-10-01", "max_temperature": 22.5, "avg_humidity": 47.5},
        {"date": "2023-10-02", "max_temperature": 19.0, "avg_humidity": 60.0},
        {"date": "2023-10-03", "max_temperature": 28.0, "avg_humidity": 52.5}
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, found {len(data)}."
    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert "date" in actual, f"Record {i} is missing 'date' key."
        assert "max_temperature" in actual, f"Record {i} is missing 'max_temperature' key."
        assert "avg_humidity" in actual, f"Record {i} is missing 'avg_humidity' key."
        assert actual["date"] == expected["date"], f"Expected date {expected['date']} at index {i}, got {actual['date']}."
        assert isinstance(actual["max_temperature"], (int, float)), f"max_temperature must be a number at index {i}."
        assert abs(actual["max_temperature"] - expected["max_temperature"]) < 1e-5, f"Expected max_temperature {expected['max_temperature']} for date {expected['date']}, got {actual['max_temperature']}."
        assert isinstance(actual["avg_humidity"], (int, float)), f"avg_humidity must be a number at index {i}."
        assert abs(actual["avg_humidity"] - expected["avg_humidity"]) < 1e-5, f"Expected avg_humidity {expected['avg_humidity']} for date {expected['date']}, got {actual['avg_humidity']}."

def test_summary_sorted():
    with open(SUMMARY_PATH, 'r') as f:
        data = json.load(f)
    dates = [row.get("date") for row in data if isinstance(row, dict) and "date" in row]
    assert dates == sorted(dates), "The JSON array is not sorted chronologically by date."
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/run_dynamic.py
import json
import os
import re
import runpy
import sqlite3 as real_sqlite3
import sys
import types
from collections import defaultdict

SCRIPT = '/home/user/process_data.py'
DB = '/home/user/sensor_data.db'
OUT = '/home/user/daily_summary.json'

assert os.path.exists(SCRIPT), f'Expected script {SCRIPT} does not exist.'
assert os.path.isfile(SCRIPT), f'Path {SCRIPT} is not a regular file.'

for suffix in ('', '-wal', '-shm'):
    try:
        os.remove(DB + suffix)
    except FileNotFoundError:
        pass

conn = real_sqlite3.connect(DB)
conn.execute('CREATE TABLE readings(id INTEGER PRIMARY KEY, station_id TEXT, timestamp TEXT, payload TEXT)')
rows = [
    (1, 'ST-01', '2041-02-03 01:00:00', json.dumps({'temperature': -2.5, 'humidity': 10.11})),
    (2, 'ST-01', '2041-02-03 22:00:00', json.dumps({'temperature': 17.75, 'humidity': 20.22})),
    (3, 'ST-01', '2041-02-04 08:00:00', 'not-json'),
    (4, 'ST-01', '2041-02-04 09:00:00', json.dumps({'temperature': 99, 'humidity': None})),
    (5, 'ST-02', '2041-02-04 10:00:00', json.dumps({'temperature': 500, 'humidity': 1})),
    (6, 'ST-01', '2041-02-05 23:59:59', json.dumps({'temperature': 31.125, 'humidity': 44.444})),
    (7, 'ST-01', '2041-02-05 00:00:01', json.dumps({'temperature': 30.5, 'humidity': 55.555})),
    (8, 'ST-01', '2041-02-04 11:00:00', json.dumps({'temperature': 8.0, 'humidity': 33.335})),
    (9, 'ST-01', '2041-02-03 12:00:00', json.dumps({'temperature': None, 'humidity': 70})),
]
conn.executemany('INSERT INTO readings VALUES (?, ?, ?, ?)', rows)
# The excluded row is valid ST-01 data, so relying on this partial timestamp
# index through an id != 6 predicate produces a detectably incomplete result.
conn.execute('CREATE INDEX idx_timestamp ON readings(timestamp) WHERE id != 6')
conn.commit()
conn.close()

# Independently derive the expected result using an explicit full scan.
conn = real_sqlite3.connect(DB)
groups = defaultdict(lambda: {'temps': [], 'hums': []})
for timestamp, payload in conn.execute("SELECT timestamp, payload FROM readings NOT INDEXED WHERE station_id = 'ST-01'"):
    try:
        value = json.loads(payload)
    except (ValueError, TypeError):
        continue
    if not isinstance(value, dict):
        continue
    temperature = value.get('temperature')
    humidity = value.get('humidity')
    if temperature is None or humidity is None:
        continue
    day = timestamp[:10]
    groups[day]['temps'].append(temperature)
    groups[day]['hums'].append(humidity)
conn.close()
expected = [
    {
        'date': day,
        'max_temperature': max(groups[day]['temps']),
        'avg_humidity': round(sum(groups[day]['hums']) / len(groups[day]['hums']), 2),
    }
    for day in sorted(groups)
]

observed_plans = []
dropped_timestamp_index = [False]

def inspect_sql(raw_conn, sql, parameters=()):
    text = str(sql)
    normalized = re.sub(r'\s+', ' ', text).strip()
    if re.search(r'\bdrop\s+index\s+(?:if\s+exists\s+)?(?:["`\[]?idx_timestamp)', normalized, re.I):
        dropped_timestamp_index[0] = True
    if re.search(r'\b(?:select|with)\b', normalized, re.I) and re.search(r'\breadings\b', normalized, re.I):
        if dropped_timestamp_index[0]:
            observed_plans.append(('dropped', normalized, []))
            return
        try:
            details = [str(row[3]) for row in raw_conn.execute('EXPLAIN QUERY PLAN ' + text, parameters)]
        except Exception as exc:
            details = ['PLAN ERROR: ' + repr(exc)]
        observed_plans.append(('planned', normalized, details))

class CursorWrapper:
    def __init__(self, cursor, connection):
        self._cursor = cursor
        self._connection = connection
    def execute(self, sql, parameters=()):
        inspect_sql(self._connection._raw, sql, parameters)
        self._cursor.execute(sql, parameters)
        return self
    def executemany(self, sql, seq):
        self._cursor.executemany(sql, seq)
        return self
    def executescript(self, script):
        for statement in script.split(';'):
            if statement.strip():
                inspect_sql(self._connection._raw, statement)
        self._cursor.executescript(script)
        return self
    def __iter__(self):
        return iter(self._cursor)
    def __getattr__(self, name):
        return getattr(self._cursor, name)

class ConnectionWrapper:
    def __init__(self, raw):
        self._raw = raw
    def cursor(self, *args, **kwargs):
        return CursorWrapper(self._raw.cursor(*args, **kwargs), self)
    def execute(self, sql, parameters=()):
        cursor = self.cursor()
        return cursor.execute(sql, parameters)
    def executemany(self, sql, seq):
        cursor = self.cursor()
        return cursor.executemany(sql, seq)
    def executescript(self, script):
        cursor = self.cursor()
        return cursor.executescript(script)
    def __enter__(self):
        self._raw.__enter__()
        return self
    def __exit__(self, *args):
        return self._raw.__exit__(*args)
    def __getattr__(self, name):
        return getattr(self._raw, name)

def wrapped_connect(*args, **kwargs):
    return ConnectionWrapper(real_sqlite3.connect(*args, **kwargs))

proxy = types.ModuleType('sqlite3')
for name in dir(real_sqlite3):
    setattr(proxy, name, getattr(real_sqlite3, name))
proxy.connect = wrapped_connect
sys.modules['sqlite3'] = proxy

try:
    os.remove(OUT)
except FileNotFoundError:
    pass
runpy.run_path(SCRIPT, run_name='__main__')

assert observed_plans, 'The script did not execute a SELECT query against the readings table.'
used_safe_scan = False
for status, sql, details in observed_plans:
    if status == 'dropped':
        used_safe_scan = True
        break
    plan = ' '.join(details).upper()
    if 'SCAN READINGS' in plan and 'USING INDEX IDX_TIMESTAMP' not in plan and 'USING COVERING INDEX IDX_TIMESTAMP' not in plan:
        used_safe_scan = True
        break
assert used_safe_scan, 'No readings query was shown to bypass idx_timestamp with a full table scan or by dropping the index. Plans: ' + repr(observed_plans)

assert os.path.isfile(OUT), f'Executing {SCRIPT} did not create {OUT}.'
with open(OUT, 'r') as f:
    actual = json.load(f)
assert isinstance(actual, list), 'The generated JSON root must be a list.'
assert actual == expected, f'Output from executing the script was incorrect. Expected {expected!r}, got {actual!r}.'
assert [row['date'] for row in actual] == sorted(row['date'] for row in actual), 'Dynamic output is not chronologically sorted.'
assert all(set(row) == {'date', 'max_temperature', 'avg_humidity'} for row in actual), 'Dynamic output records do not match the required schema.'
DYNAMIC_EOF

passed=1
if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    passed=0
fi
if [ "$passed" -eq 1 ] && ! python3 /tmp/run_dynamic.py 2>&1; then
    passed=0
fi

if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
