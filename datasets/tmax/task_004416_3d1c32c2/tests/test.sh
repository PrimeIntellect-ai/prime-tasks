#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import sqlite3
import subprocess
import tempfile
from collections import deque

import pytest

RESULT_PATH = '/home/user/result.txt'
SCRIPT_PATH = '/home/user/analyze_path.py'
DB_PATH = '/home/user/company.db'


def run_script():
    proc = subprocess.run(
        ['python3', SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert proc.returncode == 0, (
        f"analyze_path.py exited with status {proc.returncode}. "
        f"stdout: {proc.stdout!r}; stderr: {proc.stderr!r}"
    )


@pytest.fixture(scope='session', autouse=True)
def execute_submission_on_original_database():
    assert os.path.isfile(SCRIPT_PATH), f"Required Python script {SCRIPT_PATH} is missing."
    assert not os.path.islink(SCRIPT_PATH), f"{SCRIPT_PATH} must be a regular script file."
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)
    run_script()
    yield


def test_result_file_exists():
    assert os.path.exists(RESULT_PATH), f"Result file {RESULT_PATH} is missing. Did you write the output to the correct location?"


def test_result_value():
    with open(RESULT_PATH, 'r') as f:
        content = f.read().strip()

    assert content == "3", f"Expected the shortest path length to be 3, but got '{content}'."


def shortest_path_from_rows(employees, messages):
    by_name = {name: employee_id for employee_id, name, _ in employees}
    graph = {employee_id: [] for employee_id, _, _ in employees}
    for employee_id, _, manager_id in employees:
        if manager_id is not None:
            graph[employee_id].append(manager_id)
            graph[manager_id].append(employee_id)
    for sender_id, receiver_id in messages:
        graph[sender_id].append(receiver_id)

    start = by_name['Alice']
    goal = by_name['Bob']
    queue = deque([(start, 0)])
    seen = {start}
    while queue:
        node, distance = queue.popleft()
        if node == goal:
            return distance
        for neighbor in graph[node]:
            if neighbor not in seen:
                seen.add(neighbor)
                queue.append((neighbor, distance + 1))
    raise AssertionError('Generated test graph unexpectedly has no Alice-to-Bob path')


def make_database(path, target_distance, rng):
    employees = [(1, 'Alice', None)]
    previous = 1
    for offset in range(target_distance - 1):
        employee_id = 3 + offset
        employees.append((employee_id, f'Chain{offset}', previous))
        previous = employee_id
    employees.append((2, 'Bob', previous))

    next_id = 3 + max(0, target_distance - 1)
    decoy_ids = []
    while len(employees) < 12:
        employee_id = next_id
        next_id += 1
        possible_managers = [1] + decoy_ids
        employees.append((employee_id, f'Decoy{employee_id}', rng.choice(possible_managers)))
        decoy_ids.append(employee_id)

    messages = []
    if len(decoy_ids) >= 2:
        for _ in range(10):
            sender, receiver = rng.sample(decoy_ids, 2)
            messages.append((sender, receiver))

    conn = sqlite3.connect(path)
    try:
        conn.execute('CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER)')
        conn.execute('CREATE TABLE messages (sender_id INTEGER, receiver_id INTEGER)')
        conn.executemany('INSERT INTO employees VALUES (?, ?, ?)', employees)
        conn.executemany('INSERT INTO messages VALUES (?, ?)', messages)
        conn.commit()
    finally:
        conn.close()

    return employees, messages


def test_script_computes_from_database():
    rng = random.SystemRandom()
    distances = rng.sample([1, 2, 4, 5], 2)
    backup_fd, backup_path = tempfile.mkstemp(prefix='company-db-backup-', suffix='.db')
    os.close(backup_fd)
    shutil.copy2(DB_PATH, backup_path)

    try:
        for target_distance in distances:
            fd, replacement_path = tempfile.mkstemp(dir='/home/user', prefix='.company-test-', suffix='.db')
            os.close(fd)
            os.remove(replacement_path)
            employees, messages = make_database(replacement_path, target_distance, rng)
            expected = shortest_path_from_rows(employees, messages)
            assert expected == target_distance
            os.chmod(replacement_path, 0o666)
            os.replace(replacement_path, DB_PATH)

            if os.path.exists(RESULT_PATH):
                os.remove(RESULT_PATH)
            run_script()
            assert os.path.exists(RESULT_PATH), f"{SCRIPT_PATH} did not create {RESULT_PATH}."
            with open(RESULT_PATH, 'r') as f:
                content = f.read().strip()
            assert content == str(expected), (
                f"For the supplied database, expected shortest path {expected}, "
                f"but the script wrote {content!r}."
            )
    finally:
        os.replace(backup_path, DB_PATH)
        if os.path.exists(RESULT_PATH):
            os.remove(RESULT_PATH)
        try:
            run_script()
        except Exception:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
