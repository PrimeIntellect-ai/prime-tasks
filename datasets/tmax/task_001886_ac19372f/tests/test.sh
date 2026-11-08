#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_hook
cat << 'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import sqlite3

_real_connect = sqlite3.connect
_trace_file = '/tmp/etl_sql_trace.log'

def _log(sql):
    try:
        with open(_trace_file, 'a', encoding='utf-8') as f:
            f.write(str(sql))
            f.write('\n---SQL---\n')
    except Exception:
        pass

class CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, *args, **kwargs):
        _log(sql)
        self._cursor.execute(sql, *args, **kwargs)
        return self

    def executemany(self, sql, *args, **kwargs):
        _log(sql)
        self._cursor.executemany(sql, *args, **kwargs)
        return self

    def __iter__(self):
        return iter(self._cursor)

    def __next__(self):
        return next(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

class ConnectionProxy:
    def __init__(self, connection):
        self._connection = connection

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, *args, **kwargs):
        _log(sql)
        return CursorProxy(self._connection.execute(sql, *args, **kwargs))

    def executemany(self, sql, *args, **kwargs):
        _log(sql)
        return CursorProxy(self._connection.executemany(sql, *args, **kwargs))

    def executescript(self, sql, *args, **kwargs):
        _log(sql)
        return CursorProxy(self._connection.executescript(sql, *args, **kwargs))

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)

def connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = connect
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import shutil
import sqlite3
import stat
import subprocess
from collections import defaultdict

import pytest

USERS = [
    ('u1', 'NA'),
    ('u2', 'NA'),
    ('u3', 'EU'),
    ('u4', 'EU'),
    ('u5', 'ASIA'),
    ('u6', 'ASIA'),
]

EVENTS = [
    {"user_id": "u1", "event_type": "level_complete", "score": 10},
    {"user_id": "u1", "event_type": "login", "score": 0},
    {"user_id": "u1", "event_type": "level_complete", "score": 50},
    {"user_id": "u1", "event_type": "level_complete", "score": 20},
    {"user_id": "u1", "event_type": "level_complete", "score": 30},
    {"user_id": "u2", "event_type": "level_complete", "score": 40},
    {"user_id": "u2", "event_type": "level_complete", "score": 40},
    {"user_id": "u3", "event_type": "level_complete", "score": 100},
    {"user_id": "u3", "event_type": "level_complete", "score": 5},
    {"user_id": "u3", "event_type": "level_complete", "score": 5},
    {"user_id": "u3", "event_type": "level_complete", "score": 5},
    {"user_id": "u4", "event_type": "level_complete", "score": 60},
    {"user_id": "u4", "event_type": "level_complete", "score": 60},
    {"user_id": "u4", "event_type": "level_complete", "score": 60},
    {"user_id": "u4", "event_type": "level_complete", "score": 60},
    {"user_id": "u5", "event_type": "level_complete", "score": 200},
    {"user_id": "u6", "event_type": "login", "score": 10},
]

def compute_expected_data():
    # Expected values come from verifier-owned canonical data, not agent-writable files.
    user_scores = defaultdict(list)
    for event in EVENTS:
        if event.get('event_type') == 'level_complete':
            user_scores[event['user_id']].append(event['score'])

    user_top3 = {
        uid: sum(sorted(scores, reverse=True)[:3])
        for uid, scores in user_scores.items()
    }
    user_regions = dict(USERS)

    region_users = defaultdict(list)
    for uid, score in user_top3.items():
        region = user_regions.get(uid)
        if region:
            region_users[region].append({'user_id': uid, 'score': score})

    final_data = []
    region_totals = {}
    for region, users in region_users.items():
        total_score = sum(u['score'] for u in users)
        region_totals[region] = total_score
        users.sort(key=lambda x: x['score'], reverse=True)

        rank = 1
        for i, user in enumerate(users):
            if i > 0 and users[i]['score'] < users[i - 1]['score']:
                rank = i + 1
            final_data.append({
                'region': region,
                'user_id': user['user_id'],
                'user_top3_score': user['score'],
                'region_rank': rank,
                'region_total_score': total_score,
            })

    final_data.sort(key=lambda x: (x['region'], x['region_rank']))
    total_users_processed = len(user_top3)
    if region_totals:
        top_region, top_region_score = max(region_totals.items(), key=lambda x: x[1])
    else:
        top_region, top_region_score = None, 0

    return final_data, {
        'total_users_processed': total_users_processed,
        'top_region': top_region,
        'top_region_score': top_region_score,
    }

def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)

def seed_canonical_inputs():
    data_dir = '/home/user/data'
    remove_path(data_dir)
    os.makedirs(data_dir)

    db_file = os.path.join(data_dir, 'users.db')
    conn = sqlite3.connect(db_file)
    conn.execute('CREATE TABLE users (user_id TEXT PRIMARY KEY, region TEXT)')
    conn.executemany('INSERT INTO users VALUES (?, ?)', USERS)
    conn.commit()
    conn.close()

    with open(os.path.join(data_dir, 'events.jsonl'), 'w', encoding='utf-8') as f:
        for event in EVENTS:
            f.write(json.dumps(event) + '\n')

@pytest.fixture(scope='session', autouse=True)
def execute_pipeline():
    script = '/home/user/etl_pipeline.py'
    assert os.path.exists(script), f'Expected pipeline script not found at {script}'
    assert not os.path.islink(script), 'etl_pipeline.py must be a regular file, not a symlink'
    mode = os.stat(script).st_mode
    assert stat.S_ISREG(mode), 'etl_pipeline.py is not a regular file'
    assert os.path.getsize(script) > 0, 'etl_pipeline.py is empty'

    seed_canonical_inputs()
    remove_path('/home/user/output')
    trace_file = '/tmp/etl_sql_trace.log'
    remove_path(trace_file)

    env = os.environ.copy()
    env['PYTHONPATH'] = '/tmp/verifier_hook' + (
        os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else ''
    )
    result = subprocess.run(
        ['python3', script],
        cwd='/home/user',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'etl_pipeline.py exited with status {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )

    assert os.path.isfile(trace_file), 'No SQLite statements were executed by etl_pipeline.py'
    with open(trace_file, encoding='utf-8') as f:
        statements = [s for s in f.read().split('---SQL---') if s.strip()]

    rank_window = any(
        re.search(r'\brank\s*\(\s*\)\s*over\b', sql, re.I | re.S)
        and re.search(r'\bpartition\s+by\b', sql, re.I | re.S)
        for sql in statements
    )
    sum_window = any(
        re.search(r'\bsum\s*\([^)]*\)\s*over\b', sql, re.I | re.S)
        and re.search(r'\bpartition\s+by\b', sql, re.I | re.S)
        for sql in statements
    )
    assert rank_window, 'The executed SQL did not use RANK() as a partitioned window function'
    assert sum_window, 'The executed SQL did not use SUM() as a partitioned window function'

def test_csv_output():
    csv_file = '/home/user/output/region_leaderboard.csv'
    assert os.path.isfile(csv_file), f'Expected CSV output file not found at {csv_file}'

    expected_data, _ = compute_expected_data()
    with open(csv_file, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        actual_data = list(reader)
        fieldnames = reader.fieldnames

    assert fieldnames == ['region', 'user_id', 'user_top3_score', 'region_rank', 'region_total_score'], \
        'CSV header does not match expected columns'
    assert len(actual_data) == len(expected_data), \
        f'Expected {len(expected_data)} rows in CSV, but found {len(actual_data)}'

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual['region'] == expected['region'], f'Row {i + 1} region mismatch'
        assert actual['user_id'] == expected['user_id'], f'Row {i + 1} user_id mismatch'
        assert int(actual['user_top3_score']) == expected['user_top3_score'], f'Row {i + 1} user_top3_score mismatch'
        assert int(actual['region_rank']) == expected['region_rank'], f'Row {i + 1} region_rank mismatch'
        assert int(actual['region_total_score']) == expected['region_total_score'], f'Row {i + 1} region_total_score mismatch'

def test_json_output():
    json_file = '/home/user/output/etl_summary.json'
    assert os.path.isfile(json_file), f'Expected JSON output file not found at {json_file}'

    _, expected_summary = compute_expected_data()
    with open(json_file, 'r', encoding='utf-8') as f:
        try:
            actual_summary = json.load(f)
        except json.JSONDecodeError:
            assert False, 'etl_summary.json is not a valid JSON file'

    assert actual_summary.get('total_users_processed') == expected_summary['total_users_processed'], \
        'total_users_processed mismatch in JSON summary'
    assert actual_summary.get('top_region') == expected_summary['top_region'], \
        'top_region mismatch in JSON summary'
    assert actual_summary.get('top_region_score') == expected_summary['top_region_score'], \
        'top_region_score mismatch in JSON summary'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
