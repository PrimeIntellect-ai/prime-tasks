#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import sqlite3
import subprocess
import uuid

import pytest

DB_PATH = '/home/user/analytics.db'
SQL_PATH = '/home/user/optimize.sql'
PY_PATH = '/home/user/fast_report.py'
JSON_PATH = '/home/user/report_output.json'

REQUIRED_INDEXES = {
    'users': 'tenant_id',
    'sessions': 'device_type',
    'events': 'event_type',
}


def indexed_columns(conn, table):
    result = []
    for row in conn.execute(f'PRAGMA index_list("{table}")'):
        index_name = row[1]
        columns = [r[0] for r in conn.execute(
            'SELECT name FROM pragma_index_info(?) ORDER BY seqno',
            (index_name,),
        )]
        result.append(columns)
    return result


def run_report(tenant):
    if os.path.exists(JSON_PATH):
        os.unlink(JSON_PATH)
    completed = subprocess.run(
        ['python3', PY_PATH, '--tenant', tenant],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f'fast_report.py failed for {tenant}: {completed.stderr}'
    )
    assert os.path.exists(JSON_PATH), f'{JSON_PATH} was not generated.'
    with open(JSON_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{JSON_PATH} is not valid JSON.')


def test_optimize_sql_exists_and_contains_indexes():
    assert os.path.exists(SQL_PATH), f'{SQL_PATH} does not exist.'
    with open(SQL_PATH, 'r') as f:
        raw_content = f.read()
    content = raw_content.upper()
    assert 'CREATE INDEX' in content, f'{SQL_PATH} does not contain CREATE INDEX statements.'

    # Execute the submitted SQL against an equivalent empty schema and inspect
    # the indexes it actually creates, rather than trusting text or comments.
    conn = sqlite3.connect(':memory:')
    try:
        conn.executescript('''
            CREATE TABLE users (id INTEGER PRIMARY KEY, tenant_id TEXT, name TEXT, created_at TEXT);
            CREATE TABLE sessions (id INTEGER PRIMARY KEY, user_id INTEGER, start_time TEXT, end_time TEXT, device_type TEXT);
            CREATE TABLE events (id INTEGER PRIMARY KEY, session_id INTEGER, event_type TEXT, timestamp TEXT, value REAL);
        ''')
        conn.executescript(raw_content)
        for table, required_column in REQUIRED_INDEXES.items():
            definitions = indexed_columns(conn, table)
            assert any(required_column in cols for cols in definitions), (
                f'{SQL_PATH} does not create an index on {table}.{required_column}.'
            )
    finally:
        conn.close()


def test_db_has_indexes():
    conn = sqlite3.connect(DB_PATH)
    try:
        c = conn.cursor()
        c.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index';")
        indexes = c.fetchall()

        indexed_tables = [row[1] for row in indexes]
        assert 'users' in indexed_tables, "No index found on 'users' table."
        assert 'sessions' in indexed_tables, "No index found on 'sessions' table."
        assert 'events' in indexed_tables, "No index found on 'events' table."

        for table, required_column in REQUIRED_INDEXES.items():
            definitions = indexed_columns(conn, table)
            assert any(required_column in cols for cols in definitions), (
                f'No applied index includes required column {table}.{required_column}.'
            )
    finally:
        conn.close()


def test_python_script_uses_parameterized_queries():
    assert os.path.exists(PY_PATH), f'{PY_PATH} does not exist.'
    with open(PY_PATH, 'r') as f:
        content = f.read()

    # Preserve the original marker assertion.
    has_param_marker = re.search(r'\?|:\w+', content)
    assert has_param_marker is not None, (
        'The script does not appear to use parameterized queries (? or :name).'
    )

    # Verify that the marker belongs to the SQL passed to the script's single
    # execute call and that parameters are actually supplied to that call.
    tree = ast.parse(content, filename=PY_PATH)
    string_assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            if isinstance(value, ast.Constant) and isinstance(value.value, str):
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                for target in targets:
                    if isinstance(target, ast.Name):
                        string_assignments[target.id] = value.value

    execute_calls = []
    for node in ast.walk(tree):
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and node.func.attr == 'execute'):
            execute_calls.append(node)

    assert len(execute_calls) == 1, (
        'fast_report.py must perform the report with a single SQL execute call.'
    )
    call = execute_calls[0]
    assert len(call.args) >= 2, 'The SQL execute call does not bind parameters.'
    assert call.args, 'The SQL execute call is missing its query.'

    query_node = call.args[0]
    if isinstance(query_node, ast.Constant) and isinstance(query_node.value, str):
        query = query_node.value
    elif isinstance(query_node, ast.Name):
        query = string_assignments.get(query_node.id)
    else:
        query = None
    assert query is not None, 'Could not verify the SQL passed to execute().'

    normalized = re.sub(r'\s+', ' ', query).upper()
    assert re.search(r'\?|:\w+', query), 'The executed report SQL is not parameterized.'
    assert normalized.count(' JOIN ') >= 2, 'The report SQL must join all three tables.'
    for token in ('USERS', 'SESSIONS', 'EVENTS', 'SUM(', 'GROUP BY', 'ORDER BY', 'LIMIT'):
        assert token in normalized, f'The executed report SQL is missing {token}.'


def test_report_output_json():
    data = run_report('tenant_42')

    expected_data = [
        {'user_id': 139, 'name': 'User_139', 'total_purchase_value': 1599.25},
        {'user_id': 997, 'name': 'User_997', 'total_purchase_value': 1345.54},
        {'user_id': 483, 'name': 'User_483', 'total_purchase_value': 1058.46},
        {'user_id': 923, 'name': 'User_923', 'total_purchase_value': 624.93},
        {'user_id': 12,  'name': 'User_12',  'total_purchase_value': 381.16},
    ]

    assert isinstance(data, list), 'Output JSON must be a list of objects.'
    assert len(data) == len(expected_data), f'Expected {len(expected_data)} records, got {len(data)}.'

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual.get('user_id') == expected['user_id'], f"Record {i}: Expected user_id {expected['user_id']}, got {actual.get('user_id')}"
        assert actual.get('name') == expected['name'], f"Record {i}: Expected name '{expected['name']}', got '{actual.get('name')}'"
        actual_val = actual.get('total_purchase_value')
        assert actual_val is not None, f"Record {i}: Missing 'total_purchase_value'"
        assert abs(actual_val - expected['total_purchase_value']) < 0.01, f"Record {i}: Expected total_purchase_value {expected['total_purchase_value']}, got {actual_val}"


def test_report_executes_against_unseen_tenant_data():
    tenant = '__verifier_' + uuid.uuid4().hex
    other_tenant = tenant + '_other'
    seed = -(uuid.uuid4().int % 1000000000 + 1000000000)
    user_ids = [seed - i for i in range(8)]
    session_ids = [seed - 100 - i for i in range(12)]
    event_ids = [seed - 1000 - i for i in range(20)]

    users = [
        (user_ids[0], tenant, 'Zelda', '2024-01-01'),
        (user_ids[1], tenant, 'Bob', '2024-01-01'),
        (user_ids[2], tenant, 'Aaron', '2024-01-01'),
        (user_ids[3], tenant, 'Cara', '2024-01-01'),
        (user_ids[4], tenant, 'Dora', '2024-01-01'),
        (user_ids[5], tenant, 'Evan', '2024-01-01'),
        (user_ids[6], tenant, 'Finn', '2024-01-01'),
        (user_ids[7], other_tenant, 'Outsider', '2024-01-01'),
    ]
    sessions = [
        (session_ids[0], user_ids[0], '', '', 'mobile'),
        (session_ids[1], user_ids[0], '', '', 'mobile'),
        (session_ids[2], user_ids[1], '', '', 'mobile'),
        (session_ids[3], user_ids[2], '', '', 'mobile'),
        (session_ids[4], user_ids[3], '', '', 'mobile'),
        (session_ids[5], user_ids[4], '', '', 'mobile'),
        (session_ids[6], user_ids[5], '', '', 'mobile'),
        (session_ids[7], user_ids[6], '', '', 'mobile'),
        (session_ids[8], user_ids[0], '', '', 'desktop'),
        (session_ids[9], user_ids[3], '', '', 'tablet'),
        (session_ids[10], user_ids[7], '', '', 'mobile'),
    ]
    events = [
        (event_ids[0], session_ids[0], 'purchase', '', 100.0),
        (event_ids[1], session_ids[1], 'purchase', '', 25.0),
        (event_ids[2], session_ids[2], 'purchase', '', 200.0),
        (event_ids[3], session_ids[3], 'purchase', '', 200.0),
        (event_ids[4], session_ids[4], 'purchase', '', 90.0),
        (event_ids[5], session_ids[5], 'purchase', '', 80.0),
        (event_ids[6], session_ids[6], 'purchase', '', 70.0),
        (event_ids[7], session_ids[7], 'purchase', '', 60.0),
        (event_ids[8], session_ids[8], 'purchase', '', 9999.0),
        (event_ids[9], session_ids[9], 'purchase', '', 8888.0),
        (event_ids[10], session_ids[0], 'click', '', 7777.0),
        (event_ids[11], session_ids[10], 'purchase', '', 6666.0),
    ]

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executemany('INSERT INTO users VALUES (?, ?, ?, ?)', users)
        conn.executemany('INSERT INTO sessions VALUES (?, ?, ?, ?, ?)', sessions)
        conn.executemany('INSERT INTO events VALUES (?, ?, ?, ?, ?)', events)
        conn.commit()

        expected_rows = conn.execute('''
            SELECT u.id, u.name, SUM(e.value)
            FROM users AS u
            JOIN sessions AS s ON s.user_id = u.id
            JOIN events AS e ON e.session_id = s.id
            WHERE u.tenant_id = ?
              AND s.device_type = 'mobile'
              AND e.event_type = 'purchase'
            GROUP BY u.id, u.name
            ORDER BY SUM(e.value) DESC, u.name ASC
            LIMIT 5
        ''', (tenant,)).fetchall()

        actual = run_report(tenant)
        assert isinstance(actual, list), 'Output JSON must be a list of objects.'
        assert len(actual) == 5, f'Expected 5 dynamic records, got {len(actual)}.'
        for i, (item, expected) in enumerate(zip(actual, expected_rows)):
            assert isinstance(item, dict), f'Record {i} is not an object.'
            assert set(item) == {'user_id', 'name', 'total_purchase_value'}, (
                f'Record {i} has incorrect JSON fields.'
            )
            assert item['user_id'] == expected[0]
            assert item['name'] == expected[1]
            assert isinstance(item['total_purchase_value'], (int, float))
            assert abs(item['total_purchase_value'] - expected[2]) < 0.01
    finally:
        conn.executemany('DELETE FROM events WHERE id = ?', [(row[0],) for row in events])
        conn.executemany('DELETE FROM sessions WHERE id = ?', [(row[0],) for row in sessions])
        conn.executemany('DELETE FROM users WHERE id = ?', [(row[0],) for row in users])
        conn.commit()
        conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
