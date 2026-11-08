#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/sqlite_trace_hook
cat << 'PY_EOF' > /tmp/sqlite_trace_hook/sitecustomize.py
import json
import os
import sqlite3

_real_connect = sqlite3.connect

def _connect(*args, **kwargs):
    conn = _real_connect(*args, **kwargs)
    trace_path = os.environ.get('BACKUP_SQL_TRACE')
    if trace_path:
        def trace(statement):
            with open(trace_path, 'a', encoding='utf-8') as f:
                f.write(json.dumps(statement) + '\n')
        conn.set_trace_callback(trace)
    return conn

sqlite3.connect = _connect
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import subprocess

SCRIPT_PATH = '/home/user/analyze_backups.py'
DB_PATH = '/home/user/backups.db'
OUTPUT_JSON_PATH = '/home/user/failed_chains_page2.json'
TRACE_PATH = '/tmp/analyze_backups_sql_trace.jsonl'

ORIGINAL_ROWS = [
    (1, None, 'SUCCESS', 100), (2, 1, 'SUCCESS', 110), (3, 2, 'SUCCESS', 120),
    (4, None, 'SUCCESS', 200), (5, 4, 'FAILED', 210), (6, 5, 'SUCCESS', 220),
    (7, None, 'SUCCESS', 300), (8, 7, 'SUCCESS', 310), (9, 8, 'FAILED', 320),
    (10, None, 'SUCCESS', 400), (11, 10, 'SUCCESS', 410),
    (12, None, 'FAILED', 500), (13, 12, 'SUCCESS', 510), (14, 13, 'SUCCESS', 520),
    (15, None, 'SUCCESS', 600), (16, 15, 'FAILED', 610),
]

DYNAMIC_ROWS = [
    (91, None, 'SUCCESS', 1200), (92, 91, 'SUCCESS', 1210),
    (101, None, 'SUCCESS', 1100), (102, 101, 'FAILED', 1110), (103, 102, 'SUCCESS', 1120),
    (205, None, 'FAILED', 950), (207, 205, 'SUCCESS', 960),
    (311, None, 'SUCCESS', 810), (315, 311, 'SUCCESS', 820), (319, 315, 'FAILED', 830),
    (404, None, 'SUCCESS', 670), (405, 404, 'FAILED', 680),
    (550, None, 'FAILED', 540), (551, 550, 'SUCCESS', 550),
    (700, None, 'SUCCESS', 1300), (701, 700, 'SUCCESS', 1310),
]


def schema_snapshot(path):
    with sqlite3.connect(path) as conn:
        return conn.execute(
            "SELECT type, name, tbl_name, sql FROM sqlite_master "
            "WHERE name IN ('backups', 'idx_status_time') ORDER BY type, name"
        ).fetchall()


def rows_snapshot(path):
    with sqlite3.connect(path) as conn:
        return conn.execute(
            'SELECT id, parent_id, status, timestamp FROM backups ORDER BY id'
        ).fetchall()


def install_fixture(rows):
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute('CREATE TABLE backups (id INTEGER PRIMARY KEY, parent_id INTEGER, status TEXT, timestamp INTEGER)')
        conn.execute('CREATE INDEX idx_status_time ON backups(status, timestamp)')
        conn.executemany('INSERT INTO backups VALUES (?, ?, ?, ?)', rows)
        conn.commit()


def expected_page(rows):
    by_parent = {}
    by_id = {}
    for row in rows:
        by_id[row[0]] = row
        by_parent.setdefault(row[1], []).append(row[0])

    failed_chains = []
    for root in by_parent.get(None, []):
        chain = []
        current = root
        while current is not None:
            chain.append(current)
            children = by_parent.get(current, [])
            assert len(children) <= 1, 'Verifier fixtures must contain linear chains'
            current = children[0] if children else None
        if any(by_id[item][2] == 'FAILED' for item in chain):
            failed_chains.append((by_id[root][3], chain))

    failed_chains.sort(key=lambda item: item[0], reverse=True)
    return [chain for _, chain in failed_chains[2:4]]


def strip_sql_comments(sql):
    sql = re.sub(r'/\*.*?\*/', ' ', sql, flags=re.S)
    sql = re.sub(r'--[^\n]*', ' ', sql)
    return sql


def read_trace():
    if not os.path.isfile(TRACE_PATH):
        return []
    statements = []
    with open(TRACE_PATH, 'r', encoding='utf-8') as f:
        for line in f:
            if line.strip():
                statements.append(json.loads(line))
    return statements


def assert_required_query_was_executed(statements):
    mutation = re.compile(r'^\s*(DROP|ALTER|CREATE|REINDEX|INSERT|UPDATE|DELETE|REPLACE)\b', re.I)
    assert not any(mutation.search(strip_sql_comments(s)) for s in statements), \
        'The script must not modify the database data, index, or schema.'

    candidates = []
    for statement in statements:
        clean = strip_sql_comments(statement)
        if (re.search(r'\bWITH\s+RECURSIVE\b', clean, re.I)
                and re.search(r'\bbackups\b[\s\S]{0,120}?\bNOT\s+INDEXED\b', clean, re.I)
                and re.search(r'\bORDER\s+BY\b', clean, re.I)
                and re.search(r'\bDESC\b', clean, re.I)):
            candidates.append(statement)

    assert candidates, (
        'The executed SQL must use WITH RECURSIVE, apply NOT INDEXED to backups, '
        'and order the chains descending.'
    )

    usable = False
    with sqlite3.connect(DB_PATH) as conn:
        for statement in candidates:
            try:
                plan = conn.execute('EXPLAIN QUERY PLAN ' + statement).fetchall()
            except sqlite3.Error:
                continue
            plan_text = ' '.join(str(col) for row in plan for col in row).upper()
            if 'IDX_STATUS_TIME' not in plan_text and ('RECURSIVE STEP' in plan_text or 'CO-ROUTINE' in plan_text):
                usable = True
                break
    assert usable, 'The recursive query must actually bypass idx_status_time.'


def run_script_and_check(rows, expected):
    before_schema = schema_snapshot(DB_PATH)
    before_rows = rows_snapshot(DB_PATH)
    if os.path.exists(OUTPUT_JSON_PATH):
        os.remove(OUTPUT_JSON_PATH)
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)

    env = os.environ.copy()
    env['BACKUP_SQL_TRACE'] = TRACE_PATH
    env['PYTHONPATH'] = '/tmp/sqlite_trace_hook' + (':' + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    result = subprocess.run(
        ['python3', SCRIPT_PATH], cwd='/home/user', env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, f'Script failed:\n{result.stderr}'
    assert os.path.isfile(OUTPUT_JSON_PATH), f'Output JSON file not found at {OUTPUT_JSON_PATH}'

    with open(OUTPUT_JSON_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)
    assert data == expected, f'JSON output mismatch. Expected {expected}, but got {data}'

    assert schema_snapshot(DB_PATH) == before_schema, 'The script modified the database schema or index.'
    assert rows_snapshot(DB_PATH) == before_rows, 'The script modified backup records.'
    statements = read_trace()
    assert statements, 'No SQLite statements executed by the submitted script were observed.'
    assert_required_query_was_executed(statements)


def test_script_exists_and_uses_not_indexed():
    assert os.path.isfile(SCRIPT_PATH), f'Script not found at {SCRIPT_PATH}'
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        content = f.read()
    assert 'NOT INDEXED' in content.upper(), "The script must contain 'NOT INDEXED' to bypass the corrupted index."


def test_output_json_exists_and_correct():
    assert rows_snapshot(DB_PATH) == sorted(ORIGINAL_ROWS), 'The supplied backups database was modified.'
    run_script_and_check(ORIGINAL_ROWS, [[7, 8, 9], [4, 5, 6]])


def test_script_works_from_database_on_independent_fixture():
    backup_path = '/tmp/original_backups.db'
    output_backup = None
    shutil.copy2(DB_PATH, backup_path)
    if os.path.isfile(OUTPUT_JSON_PATH):
        with open(OUTPUT_JSON_PATH, 'rb') as f:
            output_backup = f.read()
    try:
        install_fixture(DYNAMIC_ROWS)
        run_script_and_check(DYNAMIC_ROWS, expected_page(DYNAMIC_ROWS))
    finally:
        shutil.copy2(backup_path, DB_PATH)
        if output_backup is None:
            if os.path.exists(OUTPUT_JSON_PATH):
                os.remove(OUTPUT_JSON_PATH)
        else:
            with open(OUTPUT_JSON_PATH, 'wb') as f:
                f.write(output_backup)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
