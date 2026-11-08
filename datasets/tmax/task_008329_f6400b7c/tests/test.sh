#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import sqlite3
import stat
import subprocess
import pytest

DB_PATH = '/home/user/backups.db'
SCRIPT_PATH = '/home/user/analyze_backups.py'
DEADLOCKS_PATH = '/home/user/deadlocks.txt'
DURATIONS_PATH = '/home/user/durations.txt'

CANONICAL_JOBS = [
    ('J1', 10),
    ('J2', 15),
    ('J3', 20),
    ('J4', 5),
    ('J5', 12),
    ('J6', 8),
    ('J7', 30),
    ('J8', 10),
]

CANONICAL_DEPS = [
    ('J2', 'J1'),
    ('J3', 'J2'),
    ('J3', 'J1'),
    ('J4', 'J5'),
    ('J5', 'J6'),
    ('J6', 'J4'),
    ('J7', 'J6'),
    ('J8', 'J3'),
]

def get_expected_data():
    if not os.path.exists(DB_PATH):
        return [], []

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT id, duration FROM jobs")
    jobs = dict(cursor.fetchall())

    cursor.execute("SELECT job_id, depends_on_id FROM dependencies")
    deps = cursor.fetchall()
    conn.close()

    graph = {job: [] for job in jobs}
    for job_id, depends_on in deps:
        if job_id in graph:
            graph[job_id].append(depends_on)

    # Cycle detection
    def find_cycles():
        visited = set()
        path = []
        in_cycle = set()

        def dfs(node):
            if node in path:
                cycle_start = path.index(node)
                for n in path[cycle_start:]:
                    in_cycle.add(n)
                return
            if node in visited:
                return

            visited.add(node)
            path.append(node)
            for neighbor in graph.get(node, []):
                dfs(neighbor)
            path.pop()

        for node in graph:
            dfs(node)

        return in_cycle

    cycles = find_cycles()

    # Transitive dependencies
    def get_all_deps(node):
        deps_set = set()
        stack = [node]
        while stack:
            curr = stack.pop()
            for n in graph.get(curr, []):
                if n not in deps_set:
                    deps_set.add(n)
                    stack.append(n)
        return deps_set

    durations = {}
    for job in jobs:
        all_deps = get_all_deps(job)
        # Check if job or any of its dependencies are in a cycle
        if job in cycles or any(dep in cycles for dep in all_deps):
            continue

        total_duration = jobs[job] + sum(jobs[dep] for dep in all_deps if dep in jobs)
        durations[job] = total_duration

    expected_deadlocks = sorted(list(cycles))
    expected_durations = [f"{job}: {durations[job]}" for job in sorted(durations.keys())]

    return expected_deadlocks, expected_durations

def write_database(jobs, deps):
    for suffix in ('', '-journal', '-wal', '-shm'):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('CREATE TABLE jobs (id TEXT PRIMARY KEY, duration INTEGER)')
    cursor.execute('CREATE TABLE dependencies (job_id TEXT, depends_on_id TEXT)')
    cursor.executemany('INSERT INTO jobs VALUES (?, ?)', jobs)
    cursor.executemany('INSERT INTO dependencies VALUES (?, ?)', deps)
    conn.commit()
    conn.close()

def database_snapshot():
    assert os.path.isfile(DB_PATH), f'{DB_PATH} was removed by the script.'
    conn = sqlite3.connect(DB_PATH)
    try:
        schema = conn.execute(
            "SELECT type, name, tbl_name, sql FROM sqlite_master "
            "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"
        ).fetchall()
        jobs = conn.execute('SELECT id, duration FROM jobs ORDER BY id').fetchall()
        deps = conn.execute(
            'SELECT job_id, depends_on_id FROM dependencies ORDER BY job_id, depends_on_id'
        ).fetchall()
        return schema, jobs, deps
    finally:
        conn.close()

def read_nonempty_lines(path):
    with open(path, 'r') as f:
        return [line.strip() for line in f if line.strip()]

def run_case(jobs, deps):
    write_database(jobs, deps)
    expected_deadlocks, expected_durations = get_expected_data()
    before = database_snapshot()

    for path in (DEADLOCKS_PATH, DURATIONS_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'{SCRIPT_PATH} exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert database_snapshot() == before, 'The analysis script modified or replaced backups.db.'
    assert os.path.isfile(DEADLOCKS_PATH), f'File {DEADLOCKS_PATH} was not created.'
    assert os.path.isfile(DURATIONS_PATH), f'File {DURATIONS_PATH} was not created.'
    assert read_nonempty_lines(DEADLOCKS_PATH) == expected_deadlocks
    assert read_nonempty_lines(DURATIONS_PATH) == expected_durations

@pytest.fixture(scope='session', autouse=True)
def execute_analysis_script():
    assert os.path.lexists(SCRIPT_PATH), f'{SCRIPT_PATH} does not exist.'
    script_stat = os.lstat(SCRIPT_PATH)
    assert stat.S_ISREG(script_stat.st_mode), f'{SCRIPT_PATH} must be a regular Python file.'
    assert script_stat.st_size > 0, f'{SCRIPT_PATH} is empty.'

    prefix = 'T' + secrets.token_hex(5)
    ids = [f'{prefix}_{letter}' for letter in 'ABCDEFGH']
    random_jobs = [
        (ids[0], 3), (ids[1], 5), (ids[2], 7), (ids[3], 11),
        (ids[4], 13), (ids[5], 17), (ids[6], 19), (ids[7], 23),
    ]
    random_deps = [
        (ids[1], ids[0]),
        (ids[2], ids[1]),
        (ids[2], ids[0]),
        (ids[3], ids[4]),
        (ids[4], ids[3]),
        (ids[5], ids[3]),
        (ids[7], ids[2]),
    ]

    # Exercise the submitted artifact on verifier-generated data, then restore and
    # exercise the database from the task before retaining its final output.
    run_case(random_jobs, random_deps)
    run_case(CANONICAL_JOBS, CANONICAL_DEPS)

def test_deadlocks_file_exists():
    assert os.path.isfile(DEADLOCKS_PATH), f"File {DEADLOCKS_PATH} was not created."

def test_durations_file_exists():
    assert os.path.isfile(DURATIONS_PATH), f"File {DURATIONS_PATH} was not created."

def test_deadlocks_content():
    expected_deadlocks, _ = get_expected_data()

    with open(DEADLOCKS_PATH, 'r') as f:
        actual_deadlocks = [line.strip() for line in f if line.strip()]

    assert actual_deadlocks == expected_deadlocks, (
        f"Contents of {DEADLOCKS_PATH} do not match expected deadlocks.\n"
        f"Expected: {expected_deadlocks}\n"
        f"Got: {actual_deadlocks}"
    )

def test_durations_content():
    _, expected_durations = get_expected_data()

    with open(DURATIONS_PATH, 'r') as f:
        actual_durations = [line.strip() for line in f if line.strip()]

    assert actual_durations == expected_durations, (
        f"Contents of {DURATIONS_PATH} do not match expected durations.\n"
        f"Expected: {expected_durations}\n"
        f"Got: {actual_durations}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
