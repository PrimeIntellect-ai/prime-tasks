#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/sitecustomize.py
import json
import os
import sqlite3

_LOG = os.environ.get("SQL_TRACE_LOG")
_real_connect = sqlite3.connect

def _log(sql):
    if _LOG and isinstance(sql, str):
        with open(_LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(sql) + "\n")

class TracingCursor(sqlite3.Cursor):
    def execute(self, sql, parameters=()):
        _log(sql)
        return super().execute(sql, parameters)

    def executemany(self, sql, seq_of_parameters):
        _log(sql)
        return super().executemany(sql, seq_of_parameters)

    def executescript(self, sql_script):
        _log(sql_script)
        return super().executescript(sql_script)

class TracingConnection(sqlite3.Connection):
    def cursor(self, *args, **kwargs):
        kwargs["factory"] = TracingCursor
        return super().cursor(*args, **kwargs)

    def execute(self, sql, parameters=()):
        _log(sql)
        return super().execute(sql, parameters)

    def executemany(self, sql, seq_of_parameters):
        _log(sql)
        return super().executemany(sql, seq_of_parameters)

    def executescript(self, sql_script):
        _log(sql_script)
        return super().executescript(sql_script)

def traced_connect(*args, **kwargs):
    kwargs["factory"] = TracingConnection
    return _real_connect(*args, **kwargs)

sqlite3.connect = traced_connect
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import sqlite3
import subprocess
import sys

import pytest

SCRIPT_PATH = '/home/user/process_data.py'
DB_PATH = '/home/user/sensor_data.db'
QUERY_PLAN_PATH = '/home/user/query_plan.txt'
JSON_OUTPUT_PATH = '/home/user/aggregated_output.json'
SENSORS_CSV = '/home/user/sensors.csv'
READINGS_CSV = '/home/user/readings.csv'
TRACE_PATH = '/tmp/process_sql_trace.jsonl'


def _normalized_sql(sql):
    return re.sub(r'\s+', ' ', sql).strip().upper()


def _is_complex_query(sql):
    normalized = _normalized_sql(sql)
    if 'JOIN' not in normalized:
        return False
    has_window = re.search(r'\bOVER\s*\(', normalized) is not None
    has_subquery = len(re.findall(r'\bSELECT\b', normalized)) >= 2
    return has_window or has_subquery


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT_PATH), f"Required script missing: {SCRIPT_PATH}"
    assert os.path.getsize(SCRIPT_PATH) > 0, "process_data.py is empty"

    for path in (DB_PATH, QUERY_PLAN_PATH, JSON_OUTPUT_PATH, TRACE_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env['PYTHONPATH'] = '/tmp' + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    env['SQL_TRACE_LOG'] = TRACE_PATH
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user', env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert result.returncode == 0, (
        f"process_data.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_database_exists_and_csv_data_was_loaded():
    assert os.path.isfile(DB_PATH), f"Database file missing: {DB_PATH}"

    with open(SENSORS_CSV, newline='', encoding='utf-8') as f:
        expected_sensors = {
            (row['sensor_id'], row['sensor_type'], row['location_id'])
            for row in csv.DictReader(f)
        }
    with open(READINGS_CSV, newline='', encoding='utf-8') as f:
        expected_readings = {
            (row['reading_id'], row['sensor_id'], float(row['reading_value']), row['timestamp'])
            for row in csv.DictReader(f)
        }

    conn = sqlite3.connect(DB_PATH)
    try:
        tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        assert 'sensors' in tables, "Table 'sensors' is missing from the database."
        assert 'readings' in tables, "Table 'readings' is missing from the database."

        actual_sensors = {
            (str(r[0]), str(r[1]), str(r[2]))
            for r in conn.execute('SELECT sensor_id, sensor_type, location_id FROM sensors')
        }
        actual_readings = {
            (str(r[0]), str(r[1]), float(r[2]), str(r[3]))
            for r in conn.execute('SELECT reading_id, sensor_id, reading_value, timestamp FROM readings')
        }
        assert actual_sensors == expected_sensors, "The sensors table was not loaded exactly from sensors.csv."
        assert actual_readings == expected_readings, "The readings table was not loaded exactly from readings.csv."
    finally:
        conn.close()


def test_meaningful_index_and_real_indexed_plan():
    conn = sqlite3.connect(DB_PATH)
    try:
        user_indexes = {}
        for table in ('sensors', 'readings'):
            for row in conn.execute(f'PRAGMA index_list("{table}")'):
                name = row[1]
                origin = row[3] if len(row) > 3 else 'c'
                if origin == 'c':
                    cols = [r[2] for r in conn.execute(f'PRAGMA index_info("{name}")')]
                    user_indexes[name] = (table, cols)

        assert user_indexes, "No user-created indexes found on sensors or readings."
        useful_reading_indexes = {
            name for name, (table, cols) in user_indexes.items()
            if table == 'readings' and {'sensor_id', 'timestamp'}.issubset(set(cols))
        }
        assert useful_reading_indexes, (
            "A composite readings index covering sensor_id and timestamp is required "
            "for the latest-reading join/query."
        )
    finally:
        conn.close()

    assert os.path.isfile(QUERY_PLAN_PATH), f"Query plan file missing: {QUERY_PLAN_PATH}"
    with open(QUERY_PLAN_PATH, encoding='utf-8') as f:
        plan = f.read().upper()
    assert 'INDEX' in plan, "Query plan does not indicate the use of an index."
    assert any(name.upper() in plan for name in useful_reading_indexes), (
        "The saved query plan does not show use of the meaningful readings index."
    )


def test_script_actually_executes_complex_sql_and_explain():
    assert os.path.isfile(TRACE_PATH), "No SQLite activity was observed while process_data.py ran."
    with open(TRACE_PATH, encoding='utf-8') as f:
        statements = [json.loads(line) for line in f if line.strip()]

    normalized = [_normalized_sql(s) for s in statements]
    assert any(re.search(r'\bCREATE\s+TABLE\b.*\bSENSORS\b', s) for s in normalized), (
        "The script did not create the sensors table through SQLite."
    )
    assert any(re.search(r'\bCREATE\s+TABLE\b.*\bREADINGS\b', s) for s in normalized), (
        "The script did not create the readings table through SQLite."
    )
    assert any(re.search(r'\bINSERT\s+INTO\s+[\"`\[]?SENSORS', s) for s in normalized), (
        "The script did not load sensors through SQLite INSERT statements."
    )
    assert any(re.search(r'\bINSERT\s+INTO\s+[\"`\[]?READINGS', s) for s in normalized), (
        "The script did not load readings through SQLite INSERT statements."
    )

    data_queries = [
        s for s in statements
        if not _normalized_sql(s).startswith('EXPLAIN') and _is_complex_query(s)
    ]
    explain_queries = [
        s for s in statements
        if re.search(r'\bEXPLAIN\s+QUERY\s+PLAN\b', _normalized_sql(s)) and _is_complex_query(s)
    ]
    assert data_queries, "The script did not execute a JOIN with a subquery or window function."
    assert explain_queries, "The script did not execute EXPLAIN QUERY PLAN for a complex JOIN query."


def test_json_output_structure_and_values():
    assert os.path.isfile(JSON_OUTPUT_PATH), f"JSON output file missing: {JSON_OUTPUT_PATH}"
    with open(JSON_OUTPUT_PATH, encoding='utf-8') as f:
        output_data = json.load(f)
    assert isinstance(output_data, list), "JSON output must be a list of objects."

    sensors = {}
    with open(SENSORS_CSV, newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            sensors[row['sensor_id']] = (row['location_id'], row['sensor_type'])

    max_timestamp = {}
    candidates = {}
    with open(READINGS_CSV, newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            if row['sensor_id'] not in sensors:
                continue
            key = sensors[row['sensor_id']]
            timestamp = row['timestamp']
            value = float(row['reading_value'])
            if key not in max_timestamp or timestamp > max_timestamp[key]:
                max_timestamp[key] = timestamp
                candidates[key] = {value}
            elif timestamp == max_timestamp[key]:
                candidates[key].add(value)

    assert len(output_data) == len(max_timestamp), (
        f"Expected {len(max_timestamp)} items in JSON output, got {len(output_data)}."
    )

    seen = set()
    required_keys = {'location_id', 'sensor_type', 'latest_timestamp', 'reading_value'}
    for item in output_data:
        assert isinstance(item, dict), "Items in JSON list must be objects."
        assert set(item) == required_keys, f"JSON object keys must be exactly {required_keys}."
        key = (item['location_id'], item['sensor_type'])
        assert key in max_timestamp, f"Unexpected location/sensor combination: {key}"
        assert key not in seen, f"More than one result was returned for {key}."
        seen.add(key)
        assert item['latest_timestamp'] == max_timestamp[key], f"Incorrect timestamp for {key}"
        assert float(item['reading_value']) in candidates[key], (
            f"Reading value for {key} is not from a reading at the maximum timestamp."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
