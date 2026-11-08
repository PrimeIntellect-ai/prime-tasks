#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import os
import re
import sqlite3
import subprocess
from collections import Counter

import pytest

HOME = '/home/user'
CSV_PATH = os.path.join(HOME, 'locks.csv')
DB_PATH = os.path.join(HOME, 'etl.db')
REPORT_PATH = os.path.join(HOME, 'report.json')
TRACE_DIR = '/tmp/etl_instrument'
TRACE_PATH = '/tmp/etl_sql_trace.log'

ORIGINAL_ROWS = [
    (1, 'A', 'GRANTED'),
    (2, 'A', 'WAITING'),
    (3, 'A', 'WAITING'),
    (4, 'B', 'GRANTED'),
    (1, 'B', 'WAITING'),
    (5, 'B', 'WAITING'),
    (6, 'C', 'GRANTED'),
    (4, 'C', 'WAITING'),
    (7, 'D', 'WAITING'),
]

ORIGINAL_EXPECTED = {
    'top_blockers': [
        {'rank': 1, 'tx_id': 1, 'blocking_score': 2},
        {'rank': 2, 'tx_id': 4, 'blocking_score': 2},
        {'rank': 3, 'tx_id': 6, 'blocking_score': 1},
        {'rank': 4, 'tx_id': 2, 'blocking_score': 0},
        {'rank': 5, 'tx_id': 3, 'blocking_score': 0},
    ]
}

SCENARIOS = [
    [
        (10, 'X', 'GRANTED'),
        (11, 'X', 'WAITING'),
        (11, 'X', 'WAITING'),
        (12, 'X', 'WAITING'),
        (20, 'Y', 'GRANTED'),
        (21, 'Y', 'WAITING'),
        (30, 'Z', 'GRANTED'),
        (40, 'W', 'WAITING'),
        (50, 'Q', 'GRANTED'),
        (10, 'Q', 'WAITING'),
    ],
    [
        (1, 'A', 'GRANTED'),
        (2, 'A', 'GRANTED'),
        (3, 'A', 'WAITING'),
        (3, 'A', 'WAITING'),
        (4, 'A', 'WAITING'),
        (5, 'B', 'GRANTED'),
        (1, 'B', 'WAITING'),
        (6, 'C', 'WAITING'),
    ],
]


def expected_report(rows):
    transactions = sorted({tx_id for tx_id, _, _ in rows})
    granted = {}
    waiting = {}
    for tx_id, resource_id, status in rows:
        target = granted if status == 'GRANTED' else waiting
        target.setdefault(resource_id, set()).add(tx_id)

    scores = {tx_id: 0 for tx_id in transactions}
    for resource_id, holders in granted.items():
        waiters = waiting.get(resource_id, set())
        for holder in holders:
            scores[holder] += len(waiters)

    ranked = sorted(transactions, key=lambda tx_id: (-scores[tx_id], tx_id))[:5]
    return {
        'top_blockers': [
            {'rank': rank, 'tx_id': tx_id, 'blocking_score': scores[tx_id]}
            for rank, tx_id in enumerate(ranked, 1)
        ]
    }


def write_csv(rows):
    with open(CSV_PATH, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['tx_id', 'resource_id', 'status'])
        writer.writerows(rows)


def assert_db_basics_and_contents(rows=None):
    assert os.path.isfile(DB_PATH), f'Database {DB_PATH} does not exist.'
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='lock_events'")
        assert cursor.fetchone() is not None, "Table 'lock_events' does not exist in the database."

        cursor.execute('SELECT COUNT(*) FROM lock_events')
        assert cursor.fetchone()[0] > 0, "Table 'lock_events' is empty."

        cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='lock_events'")
        indexes = cursor.fetchall()
        user_indexes = [idx[0] for idx in indexes if not idx[0].startswith('sqlite_')]
        assert user_indexes, "No indexes found on 'lock_events' table."

        if rows is not None:
            cursor.execute('SELECT tx_id, resource_id, status FROM lock_events')
            actual = cursor.fetchall()
            assert Counter(actual) == Counter(rows), (
                'lock_events does not exactly contain the current locks.csv rows. '
                f'Expected {Counter(rows)}, got {Counter(actual)}'
            )
    finally:
        conn.close()


def load_and_validate_report(expected):
    assert os.path.isfile(REPORT_PATH), f'Report file {REPORT_PATH} does not exist.'
    try:
        with open(REPORT_PATH, 'r') as f:
            result = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'File {REPORT_PATH} is not valid JSON: {exc}')

    assert result == expected, f'Report JSON content mismatch. Expected: {expected}. Got: {result}'
    assert type(result) is dict and set(result) == {'top_blockers'}
    assert type(result['top_blockers']) is list
    for item in result['top_blockers']:
        assert type(item) is dict
        assert set(item) == {'rank', 'tx_id', 'blocking_score'}
        assert type(item['rank']) is int
        assert type(item['tx_id']) is int
        assert type(item['blocking_score']) is int


def install_sql_tracer():
    os.makedirs(TRACE_DIR, exist_ok=True)
    with open(os.path.join(TRACE_DIR, 'sitecustomize.py'), 'w') as f:
        f.write(r'''import os
import sqlite3

_real_connect = sqlite3.connect
_trace_path = os.environ.get('ETL_SQL_TRACE')

def _record(statement):
    if _trace_path:
        with open(_trace_path, 'a') as out:
            out.write(statement.replace('\\n', ' ') + '\\n')

class TracedConnection(sqlite3.Connection):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.set_trace_callback(_record)

def traced_connect(*args, **kwargs):
    kwargs.setdefault('factory', TracedConnection)
    return _real_connect(*args, **kwargs)

sqlite3.connect = traced_connect
''')


def run_script(script, rows):
    write_csv(rows)
    for path in (DB_PATH, REPORT_PATH, TRACE_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env['PYTHONPATH'] = TRACE_DIR + os.pathsep + env.get('PYTHONPATH', '')
    env['ETL_SQL_TRACE'] = TRACE_PATH
    proc = subprocess.run(
        ['python3', script],
        cwd=HOME,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    if proc.returncode != 0:
        raise AssertionError(
            f'{script} exited with status {proc.returncode}. '
            f'stdout={proc.stdout!r}, stderr={proc.stderr!r}'
        )

    assert_db_basics_and_contents(rows)
    load_and_validate_report(expected_report(rows))

    assert os.path.isfile(TRACE_PATH), 'No executed SQLite statements were captured.'
    with open(TRACE_PATH, 'r') as f:
        trace = f.read()
    assert re.search(r'\bOVER\s*\(', trace, re.IGNORECASE), (
        'The executed SQLite statements did not use a SQL window function.'
    )


def test_existing_outputs_keep_original_assertions():
    # Preserve the original verifier's database, table population, index, and exact report checks.
    assert_db_basics_and_contents()
    load_and_validate_report(ORIGINAL_EXPECTED)


def test_pipeline_is_executable_and_data_driven():
    install_sql_tracer()
    candidates = sorted(
        path for path in glob.glob(os.path.join(HOME, '**', '*.py'), recursive=True)
        if os.path.isfile(path)
    )
    assert candidates, 'No Python ETL script was found under /home/user.'

    failures = []
    successful_script = None
    try:
        for script in candidates:
            try:
                for rows in SCENARIOS:
                    run_script(script, rows)
                successful_script = script
                break
            except Exception as exc:
                failures.append(f'{script}: {exc}')

        assert successful_script is not None, (
            'No submitted Python script regenerated the database and report correctly for '
            'independently chosen CSV inputs while executing a SQL window function.\n' +
            '\n'.join(failures)
        )
    finally:
        write_csv(ORIGINAL_ROWS)

    # Restore and revalidate the required final outputs using the working artifact.
    run_script(successful_script, ORIGINAL_ROWS)
    load_and_validate_report(ORIGINAL_EXPECTED)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
