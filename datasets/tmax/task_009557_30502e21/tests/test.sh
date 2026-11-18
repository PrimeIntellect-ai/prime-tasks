#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess
import sys
import pytest

DB_PATH = '/home/user/social_network.db'
PIPELINE_PATH = '/home/user/pipeline.py'
PATH_TXT = '/home/user/path.txt'
PATH_PROFILES = '/home/user/path_profiles.json'
TRACE_PATH = '/tmp/pipeline_sql_trace.log'
INSTRUMENT_DIR = '/tmp/pipeline_instrument'


def install_sql_trace_instrumentation():
    os.makedirs(INSTRUMENT_DIR, exist_ok=True)
    sitecustomize = r'''import os
import sqlite3

_original_connect = sqlite3.connect

def _traced_connect(*args, **kwargs):
    connection = _original_connect(*args, **kwargs)
    trace_path = os.environ.get("PIPELINE_SQL_TRACE")
    if trace_path:
        def _record(statement):
            with open(trace_path, "a", encoding="utf-8") as trace_file:
                trace_file.write(statement)
                trace_file.write("\n-- statement boundary --\n")
        connection.set_trace_callback(_record)
    return connection

sqlite3.connect = _traced_connect
'''
    with open(os.path.join(INSTRUMENT_DIR, 'sitecustomize.py'), 'w', encoding='utf-8') as f:
        f.write(sitecustomize)


def run_pipeline():
    for path in (PATH_TXT, PATH_PROFILES, TRACE_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env['PIPELINE_SQL_TRACE'] = TRACE_PATH
    old_pythonpath = env.get('PYTHONPATH')
    env['PYTHONPATH'] = INSTRUMENT_DIR + (os.pathsep + old_pythonpath if old_pythonpath else '')
    result = subprocess.run(
        [sys.executable, PIPELINE_PATH],
        cwd='/home/user',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{PIPELINE_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(PATH_TXT), f"Running {PIPELINE_PATH} did not create {PATH_TXT}."
    assert os.path.isfile(PATH_PROFILES), f"Running {PIPELINE_PATH} did not create {PATH_PROFILES}."

    trace = ''
    if os.path.isfile(TRACE_PATH):
        with open(TRACE_PATH, 'r', encoding='utf-8') as f:
            trace = f.read()
    recursive_statements = [
        statement for statement in trace.split('-- statement boundary --')
        if re.search(r'\bWITH\s+RECURSIVE\b', statement, re.IGNORECASE)
    ]
    assert recursive_statements, "pipeline.py did not execute a WITH RECURSIVE CTE."
    graph_ctes = [
        statement for statement in recursive_statements
        if re.search(r'\bconnections\b', statement, re.IGNORECASE)
        and re.search(r'\buser_id\b', statement, re.IGNORECASE)
        and re.search(r'\bfriend_id\b', statement, re.IGNORECASE)
        and re.search(r'\binteraction_score\b', statement, re.IGNORECASE)
    ]
    assert graph_ctes, (
        "pipeline.py executed a recursive CTE, but it was not a graph traversal over "
        "connections using user_id, friend_id, and interaction_score."
    )


def derive_optimal_path(conn, start=10, target=42):
    edges = conn.execute(
        'SELECT user_id, friend_id, interaction_score FROM connections'
    ).fetchall()
    adjacency = {}
    nodes = {start, target}
    for user_id, friend_id, score in edges:
        adjacency.setdefault(user_id, []).append((friend_id, score))
        nodes.update((user_id, friend_id))

    frontier = [([start], 0)]
    for _ in range(max(1, len(nodes))):
        candidates = [(path, score) for path, score in frontier if path[-1] == target]
        if candidates:
            return max(candidates, key=lambda item: item[1])[0]
        next_frontier = []
        for path, total_score in frontier:
            for friend_id, edge_score in adjacency.get(path[-1], []):
                if friend_id not in path:
                    next_frontier.append((path + [friend_id], total_score + edge_score))
        frontier = next_frontier
    raise AssertionError(f'No path from {start} to {target} exists in the test database.')


def expected_profiles(conn, path):
    result = []
    for order, user_id in enumerate(path):
        row = conn.execute(
            'SELECT profile_json FROM users WHERE user_id = ?', (user_id,)
        ).fetchone()
        assert row is not None, f'No profile exists for user {user_id}.'
        profile = json.loads(row[0])
        profile['path_order'] = order
        result.append(profile)
    return result


def test_pipeline_exists_runs_and_uses_recursive_cte():
    assert os.path.isfile(PIPELINE_PATH), f"Required Python script {PIPELINE_PATH} is missing."
    assert os.path.getsize(PIPELINE_PATH) > 0, f"Required Python script {PIPELINE_PATH} is empty."
    install_sql_trace_instrumentation()

    # First run against the original database. These generated files are retained
    # for the original exact-output assertions below.
    run_pipeline()
    with open(PATH_TXT, 'rb') as f:
        baseline_path = f.read()
    with open(PATH_PROFILES, 'rb') as f:
        baseline_profiles = f.read()

    conn = sqlite3.connect(DB_PATH)
    original_scores = conn.execute(
        'SELECT rowid, interaction_score FROM connections'
    ).fetchall()
    original_profiles = conn.execute(
        'SELECT user_id, profile_json FROM users'
    ).fetchall()

    try:
        # Change which equal-hop route wins and replace profile contents. This
        # prevents fixed output constants from passing as a working pipeline.
        conn.execute(
            'UPDATE connections SET interaction_score = 100 WHERE user_id = 10 AND friend_id = 99'
        )
        conn.execute(
            'UPDATE connections SET interaction_score = 100 WHERE user_id = 99 AND friend_id = 42'
        )
        conn.execute(
            'UPDATE connections SET interaction_score = 1 WHERE user_id = 10 AND friend_id = 88'
        )
        conn.execute(
            'UPDATE connections SET interaction_score = 1 WHERE user_id = 88 AND friend_id = 42'
        )
        for user_id, _ in original_profiles:
            changed = {'dynamic_user': user_id, 'verification_marker': f'profile-{user_id}'}
            conn.execute(
                'UPDATE users SET profile_json = ? WHERE user_id = ?',
                (json.dumps(changed), user_id),
            )
        conn.commit()

        expected_path = derive_optimal_path(conn)
        expected_json = expected_profiles(conn, expected_path)
        assert expected_path == [10, 99, 42], 'Verifier fixture did not produce the intended unique route.'

        run_pipeline()
        with open(PATH_TXT, 'r', encoding='utf-8') as f:
            actual_path = f.read().strip()
        assert actual_path == ','.join(map(str, expected_path)), (
            f'pipeline.py did not compute the optimal path for the current database: {actual_path}'
        )
        with open(PATH_PROFILES, 'r', encoding='utf-8') as f:
            actual_profiles = json.load(f)
        assert actual_profiles == expected_json, (
            'pipeline.py did not extract and annotate the current database profiles correctly.'
        )
    finally:
        for rowid, score in original_scores:
            conn.execute(
                'UPDATE connections SET interaction_score = ? WHERE rowid = ?', (score, rowid)
            )
        for user_id, profile_json in original_profiles:
            conn.execute(
                'UPDATE users SET profile_json = ? WHERE user_id = ?', (profile_json, user_id)
            )
        conn.commit()
        conn.close()
        with open(PATH_TXT, 'wb') as f:
            f.write(baseline_path)
        with open(PATH_PROFILES, 'wb') as f:
            f.write(baseline_profiles)


def test_indexes_optimized():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Check that only idx_cover exists on connections
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='connections';")
    indexes = {row[0] for row in cursor.fetchall()}

    assert 'idx_cover' in indexes, "Index 'idx_cover' was not created."
    assert len(indexes) == 1, f"Expected only 'idx_cover' on connections table, but found: {indexes}"

    # Check columns in idx_cover
    cursor.execute("PRAGMA index_info('idx_cover');")
    columns = [row[2] for row in cursor.fetchall()]

    assert len(columns) == 3, f"Index 'idx_cover' should cover 3 columns, but covers {len(columns)}."
    assert columns[0] == 'user_id', f"First column of 'idx_cover' must be 'user_id' for efficient filtering, found '{columns[0]}'."
    assert set(columns) == {'user_id', 'friend_id', 'interaction_score'}, f"Index 'idx_cover' does not cover the correct columns. Found: {columns}"

    conn.close()


def test_path_txt_output():
    assert os.path.isfile(PATH_TXT), f"Output file {PATH_TXT} is missing."

    with open(PATH_TXT, 'r') as f:
        content = f.read().strip()

    assert content == '10,88,42', f"Expected path '10,88,42', but got '{content}'."


def test_path_profiles_json_output():
    assert os.path.isfile(PATH_PROFILES), f"Output file {PATH_PROFILES} is missing."

    with open(PATH_PROFILES, 'r') as f:
        try:
            profiles = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {PATH_PROFILES} does not contain valid JSON.")

    expected_profiles = [
        {"name": "User 10", "age": 20, "path_order": 0},
        {"name": "User 88", "age": 28, "path_order": 1},
        {"name": "User 42", "age": 22, "path_order": 2}
    ]

    assert profiles == expected_profiles, f"JSON profiles do not match expected output.\nExpected: {expected_profiles}\nGot: {profiles}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
