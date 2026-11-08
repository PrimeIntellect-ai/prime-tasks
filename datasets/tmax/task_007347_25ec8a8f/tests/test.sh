#!/bin/bash
set -u
mkdir -p /logs/verifier
cp /home/user/data.csv /tmp/verifier_data.csv
trap 'cp /tmp/verifier_data.csv /home/user/data.csv' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import sqlite3
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
PROCESS_BIN = '/tmp/verifier_process'
AGGREGATE_BIN = '/tmp/verifier_aggregate'


def run(cmd):
    return subprocess.run(
        cmd,
        cwd=HOME,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )


def expected_from_csv():
    rows = []
    with open(HOME / 'data.csv', encoding='utf-8') as f:
        header = f.readline().rstrip('\n').split(',')
        assert header == ['id', 'user_id', 'event_type', 'payload']
        for line in f:
            if not line.strip():
                continue
            parts = line.rstrip('\n').split(',', 3)
            assert len(parts) == 4
            event_id, user_id, event_type, payload = parts
            document = json.loads(payload)
            rows.append((int(event_id), int(user_id), event_type, document))
    return rows


def expected_totals(rows=None):
    rows = expected_from_csv() if rows is None else rows
    totals = {}
    for _, user_id, _, document in rows:
        totals[user_id] = totals.get(user_id, 0) + int(document['duration'])
    return totals


def load_output():
    path = HOME / 'output.json'
    assert path.is_file(), f'Expected file {path} to exist.'
    try:
        with path.open(encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'File {path} does not contain valid JSON: {exc}')
    return data


def assert_output_matches(totals):
    data = load_output()
    assert isinstance(data, list), 'Expected output.json to contain a JSON array.'
    assert len(data) == len(totals), f'Expected {len(totals)} aggregated records, but found {len(data)}.'

    seen = set()
    for item in data:
        assert isinstance(item, dict)
        assert 'user_id' in item, 'Missing user_id in JSON object.'
        assert 'total_duration' in item, 'Missing total_duration in JSON object.'
        user_id = item['user_id']
        total_duration = item['total_duration']
        assert isinstance(user_id, int) and not isinstance(user_id, bool)
        assert isinstance(total_duration, int) and not isinstance(total_duration, bool)
        assert user_id not in seen, f'Duplicate user_id {user_id} in output.json.'
        seen.add(user_id)
        assert user_id in totals, f'Unexpected user_id {user_id} in output.'
        assert totals[user_id] == total_duration

    assert seen == set(totals)
    durations = [item['total_duration'] for item in data]
    assert durations == sorted(durations, reverse=True), 'Expected output to be sorted by total_duration in descending order.'


def assert_database_matches_csv():
    rows = expected_from_csv()
    db_path = HOME / 'events.db'
    assert db_path.is_file(), f'Expected database {db_path} to exist.'

    with sqlite3.connect(db_path) as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='events'")
        assert cursor.fetchone() is not None, "Table 'events' does not exist in the database."
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='users'")
        assert cursor.fetchone() is not None, "Table 'users' does not exist in the database."

        actual = cursor.execute(
            'SELECT id, user_id, event_type, payload FROM events ORDER BY id'
        ).fetchall()
        assert len(actual) == len(rows)
        normalized = []
        for event_id, user_id, event_type, payload in actual:
            normalized.append((event_id, user_id, event_type, json.loads(payload)))
        assert normalized == rows, 'The events table does not exactly match data.csv.'

        actual_users = {row[0] for row in cursor.execute('SELECT user_id FROM users')}
        assert actual_users == {row[1] for row in rows}


def assert_user_id_index():
    with sqlite3.connect(HOME / 'events.db') as conn:
        indexes = conn.execute("PRAGMA index_list('events')").fetchall()
        matching = []
        for index in indexes:
            name = index[1]
            columns = [row[2] for row in conn.execute(f'PRAGMA index_info({json.dumps(name)})')]
            if columns == ['user_id']:
                matching.append(name)
        assert matching, "Expected an index specifically on events(user_id)."


def assert_plan_valid():
    path = HOME / 'plan.txt'
    assert path.is_file(), f'Expected file {path} to exist.'
    content = path.read_text(encoding='utf-8')
    upper = content.upper()
    assert 'EVENTS' in upper, "Expected the query plan to reference the 'events' table."
    assert 'SCAN' in upper or 'SEARCH' in upper, "Expected the query plan to contain 'SCAN' or 'SEARCH'."

    valid_row = False
    for line in content.splitlines():
        fields = line.replace('|', ' ').split()
        if len(fields) >= 4:
            try:
                int(fields[0]); int(fields[1]); int(fields[2])
            except ValueError:
                continue
            detail = ' '.join(fields[3:]).upper()
            if 'EVENTS' in detail and ('SCAN' in detail or 'SEARCH' in detail):
                valid_row = True
                break
    assert valid_row, 'plan.txt does not contain raw EXPLAIN QUERY PLAN row output.'


def test_00_scripts_compile_and_run_cleanly():
    process = HOME / 'process.go'
    aggregate = HOME / 'aggregate.go'
    assert process.is_file(), f'Expected file {process} to exist.'
    assert aggregate.is_file(), f'Expected file {aggregate} to exist.'

    run(['go', 'build', '-o', PROCESS_BIN, str(process)])
    run(['go', 'build', '-o', AGGREGATE_BIN, str(aggregate)])

    for path in (HOME / 'events.db', HOME / 'output.json', HOME / 'plan.txt'):
        path.unlink(missing_ok=True)
    run([PROCESS_BIN])
    run([AGGREGATE_BIN])


def test_events_db_populated():
    assert_database_matches_csv()
    with sqlite3.connect(HOME / 'events.db') as conn:
        count = conn.execute('SELECT COUNT(*) FROM events').fetchone()[0]
    assert count == 6, f"Expected 6 records in the 'events' table, but found {count}."


def test_aggregate_go_uses_sqlite_json_aggregation():
    source = (HOME / 'aggregate.go').read_text(encoding='utf-8')
    assert re.search(r'(?i)\bSUM\s*\(', source), 'Aggregation query must use SQLite SUM.'
    assert re.search(r'(?i)(JSON_EXTRACT\s*\(|->>?)', source), 'Aggregation query must use SQLite JSON functions/operators.'


def test_output_json_correct():
    totals = expected_totals()
    assert totals == {101: 20, 104: 20, 102: 18, 103: 2}
    assert_output_matches(totals)


def test_index_created():
    assert_user_id_index()


def test_plan_txt_exists_and_valid():
    assert_plan_valid()


def test_dynamic_ingestion_and_aggregation():
    token = secrets.randbelow(800000) + 200000
    user_a = 1000000 + token
    user_b = 2000000 + token
    duration_a = secrets.randbelow(40) + 31
    duration_b = secrets.randbelow(40) + 71

    with open(HOME / 'data.csv', 'a', encoding='utf-8') as f:
        f.write(f'700001,{user_a},probe,{{"duration":{duration_a}}}\n')
        f.write(f'700002,{user_b},probe,{{"kind":"dynamic","duration":{duration_b}}}\n')

    for path in (HOME / 'events.db', HOME / 'output.json', HOME / 'plan.txt'):
        path.unlink(missing_ok=True)
    run([PROCESS_BIN])
    assert_database_matches_csv()
    run([AGGREGATE_BIN])

    assert_output_matches(expected_totals())
    assert_user_id_index()
    assert_plan_valid()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
