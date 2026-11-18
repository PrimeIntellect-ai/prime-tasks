#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/verifier_hook

cat << 'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import json
import os
import sqlite3

_real_connect = sqlite3.connect
_log_path = os.environ.get('SQL_TRACE_LOG')

def _record(sql, parameters):
    if not _log_path:
        return
    try:
        params = parameters
        json.dumps(params)
    except Exception:
        params = repr(parameters)
    with open(_log_path, 'a') as f:
        f.write(json.dumps({'sql': sql, 'params': params}, default=repr) + '\n')

class CursorProxy:
    def __init__(self, cursor):
        object.__setattr__(self, '_cursor', cursor)

    def execute(self, sql, parameters=()):
        result = self._cursor.execute(sql, parameters)
        _record(sql, parameters)
        return self

    def executemany(self, sql, seq_of_parameters):
        raise AssertionError('The analysis must execute one parameterized query, not executemany().')

    def executescript(self, sql_script):
        raise AssertionError('The analysis must execute one parameterized query, not executescript().')

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

    def __setattr__(self, name, value):
        setattr(self._cursor, name, value)

class ConnectionProxy:
    def __init__(self, connection):
        object.__setattr__(self, '_connection', connection)

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, parameters=()):
        cursor = self._connection.execute(sql, parameters)
        _record(sql, parameters)
        return CursorProxy(cursor)

    def executemany(self, sql, seq_of_parameters):
        raise AssertionError('The analysis must execute one parameterized query, not executemany().')

    def executescript(self, sql_script):
        raise AssertionError('The analysis must execute one parameterized query, not executescript().')

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)

    def __setattr__(self, name, value):
        setattr(self._connection, name, value)

def connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = connect
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess

SCRIPT_PATH = '/home/user/analyze.py'
OUTPUT_PATH = '/home/user/output.json'
DB_PATH = '/home/user/network.db'
TRACE_PATH = '/tmp/analyze_sql_trace.jsonl'
HOOK_PATH = '/tmp/verifier_hook'
BACKUP_PATH = '/tmp/network.db.verifier-backup'


def strip_sql_comments_and_literals(sql):
    sql = re.sub(r'/\*.*?\*/', ' ', sql, flags=re.S)
    sql = re.sub(r'--[^\n]*', ' ', sql)
    sql = re.sub(r"'(?:''|[^'])*'", "''", sql)
    sql = re.sub(r'"(?:""|[^"])*"', '""', sql)
    return sql


def flatten_params(params):
    if isinstance(params, dict):
        return list(params.values())
    if isinstance(params, (list, tuple)):
        return list(params)
    return [params]


def assert_executed_query(region, limit, offset):
    assert os.path.exists(TRACE_PATH), 'No SQLite query execution was recorded.'
    with open(TRACE_PATH) as f:
        records = [json.loads(line) for line in f if line.strip()]

    assert len(records) == 1, f'Script must execute exactly one SQL query; recorded {len(records)}.'
    record = records[0]
    sql = record['sql']
    assert isinstance(sql, str), 'Executed SQL must be a string.'
    clean = strip_sql_comments_and_literals(sql)
    upper = clean.upper().lstrip()

    assert upper.startswith('WITH ' ) or upper.startswith('WITH\n') or upper.startswith('WITH\t') or upper.startswith('WITH RECURSIVE '), 'The executed query must use a CTE.'
    assert re.search(r'\bOVER\b', upper), 'The executed query must use a window OVER clause.'
    assert re.search(r'\b(?:RANK|DENSE_RANK)\s*\(\s*\)', upper), 'The executed query must call RANK() or DENSE_RANK().' 
    assert '?' in clean or re.search(r'[:@$][A-Za-z_][A-Za-z0-9_]*', clean), 'The executed query must contain parameter markers.'

    values = flatten_params(record.get('params', []))
    value_strings = [str(value) for value in values]
    assert str(region) in value_strings, 'region_name must be supplied as a bound SQL parameter.'
    assert str(limit) in value_strings, 'limit must be supplied as a bound SQL parameter.'
    assert str(offset) in value_strings, 'offset must be supplied as a bound SQL parameter.'

    # Confirm that the recorded window function is part of the executable query,
    # rather than text hidden in a comment or string literal.
    conn = sqlite3.connect(DB_PATH)
    try:
        explain_rows = conn.execute('EXPLAIN ' + sql, record.get('params', [])).fetchall()
    finally:
        conn.close()
    opcode_details = ' '.join(str(row[5] or '') for row in explain_rows).lower()
    assert 'rank(' in opcode_details or 'dense_rank(' in opcode_details, 'RANK()/DENSE_RANK() must be an active part of the executed query.'


def run_script(region, limit, offset):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)

    env = os.environ.copy()
    env['SQL_TRACE_LOG'] = TRACE_PATH
    env['PYTHONPATH'] = HOOK_PATH + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    result = subprocess.run(
        ['python3', SCRIPT_PATH, region, str(limit), str(offset)],
        capture_output=True,
        text=True,
        env=env,
    )
    assert result.returncode == 0, f'Script execution failed with error: {result.stderr}'
    assert os.path.exists(OUTPUT_PATH), f'Output file {OUTPUT_PATH} was not created.'
    with open(OUTPUT_PATH) as f:
        data = json.load(f)
    assert_executed_query(region, limit, offset)
    return data


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f'Python script {SCRIPT_PATH} does not exist.'
    assert os.path.isfile(SCRIPT_PATH), f'Path {SCRIPT_PATH} is not a file.'


def test_script_content_constraints():
    with open(SCRIPT_PATH, 'r') as f:
        content = f.read()

    upper_content = content.upper()
    assert '?' in content or ':' in content, "Script must use parameterized queries ('?' or named parameters)."
    assert 'WITH ' in upper_content, 'Script must use SQLite CTEs (WITH clause).'
    assert 'OVER' in upper_content, 'Script must use Window Functions (OVER clause).'
    assert 'RANK()' in upper_content or 'DENSE_RANK()' in upper_content, 'Script must use RANK() or DENSE_RANK().'
    assert 'for ' not in content and 'while ' not in content, 'Script must not use Python loops for processing data.'


def test_execution_and_output_north():
    data = run_script('North', 3, 1)
    expected = [
        {'id': 'E4', 'type': 'Corp', 'region': 'South', 'total_received': 200.0, 'regional_rank': 1},
        {'id': 'E5', 'type': 'Bank', 'region': 'East', 'total_received': 300.0, 'regional_rank': 1},
        {'id': 'E3', 'type': 'Retail', 'region': 'South', 'total_received': 50.0, 'regional_rank': 2},
    ]
    assert data == expected, f'Output JSON does not match expected results.\nExpected: {expected}\nGot: {data}'


def test_execution_and_output_east():
    data = run_script('East', 10, 0)
    expected = [
        {'id': 'E6', 'type': 'Retail', 'region': 'East', 'total_received': 150.0, 'regional_rank': 1}
    ]
    assert data == expected, f'Output JSON does not match expected results for region East.\nExpected: {expected}\nGot: {data}'


def build_random_database():
    token = secrets.token_hex(5)
    ids = {name: f'{name}_{token}' for name in ['s1', 's2', 'mid', 'a', 'b', 'c', 'd', 'donor', 'unreached']}
    regions = {
        'seed': f'seed_{secrets.token_hex(4)}',
        'x': f'x_{secrets.token_hex(4)}',
        'y': f'y_{secrets.token_hex(4)}',
        'm': f'm_{secrets.token_hex(4)}',
        'z': f'z_{secrets.token_hex(4)}',
    }
    entities = [
        (ids['s1'], 'SourceOne', regions['seed']),
        (ids['s2'], 'SourceTwo', regions['seed']),
        (ids['mid'], 'Middle', regions['m']),
        (ids['a'], 'Alpha', regions['x']),
        (ids['b'], 'Beta', regions['x']),
        (ids['c'], 'Gamma', regions['y']),
        (ids['d'], 'ThirdHop', regions['x']),
        (ids['donor'], 'External', regions['z']),
        (ids['unreached'], 'Unreached', regions['x']),
    ]
    transfers = [
        (ids['s1'], ids['mid'], 11.0, 1),
        (ids['s2'], ids['a'], 7.0, 2),
        (ids['mid'], ids['b'], 13.0, 3),
        (ids['a'], ids['c'], 17.0, 4),
        (ids['s1'], ids['b'], 19.0, 5),
        (ids['donor'], ids['a'], 100.0, 6),
        (ids['donor'], ids['b'], 75.0, 7),
        (ids['donor'], ids['c'], 80.0, 8),
        (ids['c'], ids['d'], 500.0, 9),
        (ids['donor'], ids['unreached'], 900.0, 10),
    ]

    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    conn.execute('CREATE TABLE entities (id TEXT PRIMARY KEY, type TEXT, region TEXT)')
    conn.execute('CREATE TABLE transfers (source_id TEXT, target_id TEXT, amount REAL, timestamp INTEGER)')
    conn.executemany('INSERT INTO entities VALUES (?, ?, ?)', entities)
    conn.executemany('INSERT INTO transfers VALUES (?, ?, ?, ?)', transfers)
    conn.commit()
    conn.close()
    return entities, transfers, regions


def derive_expected(entities, transfers, region_name, limit, offset):
    entity_by_id = {row[0]: row for row in entities}
    starts = {row[0] for row in entities if row[2] == region_name}
    first = {target for source, target, amount, timestamp in transfers if source in starts}
    second = {target for source, target, amount, timestamp in transfers if source in first}
    reached = first | second

    totals = {}
    for source, target, amount, timestamp in transfers:
        totals[target] = totals.get(target, 0.0) + amount

    by_region = {}
    for entity_id in reached:
        row = entity_by_id[entity_id]
        by_region.setdefault(row[2], []).append(entity_id)

    ranks = {}
    for region, member_ids in by_region.items():
        ordered = sorted(member_ids, key=lambda entity_id: (-totals.get(entity_id, 0.0), entity_id))
        for position, entity_id in enumerate(ordered, 1):
            ranks[entity_id] = position

    result = []
    for entity_id in reached:
        row = entity_by_id[entity_id]
        result.append({
            'id': entity_id,
            'type': row[1],
            'region': row[2],
            'total_received': totals.get(entity_id, 0.0),
            'regional_rank': ranks[entity_id],
        })
    result.sort(key=lambda item: (item['regional_rank'], item['id']))
    return result[offset:offset + limit]


def test_randomized_graph_aggregation_ranking_and_pagination():
    shutil.copy2(DB_PATH, BACKUP_PATH)
    try:
        entities, transfers, regions = build_random_database()
        cases = [
            (regions['seed'], 20, 0),
            (regions['seed'], 2, 1),
            (regions['z'], 3, 2),
        ]
        for region, limit, offset in cases:
            expected = derive_expected(entities, transfers, region, limit, offset)
            actual = run_script(region, limit, offset)
            assert actual == expected, f'Incorrect result for randomized case {(region, limit, offset)}.\nExpected: {expected}\nGot: {actual}'
    finally:
        if os.path.exists(BACKUP_PATH):
            shutil.move(BACKUP_PATH, DB_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
