#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import shutil
import sqlite3
import stat
import subprocess

import pytest

SCRIPT_PATH = '/home/user/find_deadlock.py'
DB_PATH = '/home/user/transactions.db'
JSON_PATH = '/home/user/processes.json'
REPORT_PATH = '/home/user/deadlock_report.txt'


def remove_path(path):
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)


def run_script():
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'find_deadlock.py exited with {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


@pytest.fixture(scope='session', autouse=True)
def execute_submission_on_original_inputs():
    assert os.path.exists(SCRIPT_PATH), f'Script missing at {SCRIPT_PATH}'
    assert not os.path.islink(SCRIPT_PATH), 'find_deadlock.py must be a regular script, not a symlink'
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), 'find_deadlock.py is not a regular file'

    remove_path(REPORT_PATH)
    run_script()
    yield


def test_deadlock_report_exists():
    assert os.path.isfile(REPORT_PATH), f'Report file missing at {REPORT_PATH}'


def test_deadlock_report_content():
    with open(REPORT_PATH, 'r') as f:
        content = f.read().strip()

    assert content == '101,102,103', f"Expected '101,102,103', but got '{content}'"


def make_dynamic_inputs(cycle_length):
    rng = random.SystemRandom()
    ids = rng.sample(range(10000, 90000), cycle_length + 6)
    cycle = ids[:cycle_length]
    sys_user, sys_process, chain_waiter, chain_holder, lone_user, extra_user = ids[cycle_length:]
    resources = rng.sample(range(100000, 900000), cycle_length + 4)

    processes = [
        *({'process_id': pid, 'owner': 'user', 'priority': rng.randrange(1, 10)} for pid in cycle),
        {'process_id': sys_user, 'owner': 'user', 'priority': 2},
        {'process_id': sys_process, 'owner': 'system', 'priority': 9},
        {'process_id': chain_waiter, 'owner': 'user', 'priority': 3},
        {'process_id': chain_holder, 'owner': 'user', 'priority': 4},
        {'process_id': lone_user, 'owner': 'user', 'priority': 1},
        {'process_id': extra_user, 'owner': 'user', 'priority': 5},
    ]

    rows = []
    # Every cycle process grants its own resource and waits for the next
    # process's resource, producing exactly one all-user cycle.
    for i, pid in enumerate(cycle):
        rows.append((pid, resources[i], 'GRANTED'))
        rows.append((pid, resources[(i + 1) % cycle_length], 'WAITING'))

    # A second raw lock cycle must disappear after owner filtering because one
    # endpoint is system-owned.
    sys_r1, sys_r2 = resources[cycle_length:cycle_length + 2]
    rows.extend([
        (sys_user, sys_r1, 'GRANTED'),
        (sys_user, sys_r2, 'WAITING'),
        (sys_process, sys_r2, 'GRANTED'),
        (sys_process, sys_r1, 'WAITING'),
    ])

    # Disconnected, acyclic user-owned dependencies and irrelevant processes.
    chain_resource = resources[cycle_length + 2]
    rows.extend([
        (chain_holder, chain_resource, 'GRANTED'),
        (chain_waiter, chain_resource, 'WAITING'),
        (lone_user, resources[cycle_length + 3], 'GRANTED'),
    ])

    rng.shuffle(processes)
    rng.shuffle(rows)
    locks = [(index + 1, pid, resource, status)
             for index, (pid, resource, status) in enumerate(rows)]
    return locks, processes, ','.join(str(pid) for pid in sorted(cycle))


def install_inputs(locks, processes):
    for suffix in ('', '-wal', '-shm', '-journal'):
        remove_path(DB_PATH + suffix)

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute(
            'CREATE TABLE locks ('
            'lock_id INTEGER PRIMARY KEY, process_id INTEGER, '
            'resource_id INTEGER, status TEXT)'
        )
        conn.executemany('INSERT INTO locks VALUES (?, ?, ?, ?)', locks)
        conn.commit()
    finally:
        conn.close()

    with open(JSON_PATH, 'w') as f:
        json.dump(processes, f)


@pytest.mark.parametrize('cycle_length', [2, 4])
def test_script_computes_report_from_database_and_json(cycle_length):
    original_db = open(DB_PATH, 'rb').read()
    original_json = open(JSON_PATH, 'rb').read()
    original_report = open(REPORT_PATH, 'rb').read() if os.path.isfile(REPORT_PATH) else None

    try:
        locks, processes, expected = make_dynamic_inputs(cycle_length)
        install_inputs(locks, processes)
        remove_path(REPORT_PATH)
        run_script()

        assert os.path.isfile(REPORT_PATH), 'Script did not create deadlock_report.txt'
        with open(REPORT_PATH, 'r') as f:
            actual = f.read().strip()
        assert actual == expected, f"Expected dynamically derived report '{expected}', got '{actual}'"
    finally:
        for suffix in ('', '-wal', '-shm', '-journal'):
            remove_path(DB_PATH + suffix)
        with open(DB_PATH, 'wb') as f:
            f.write(original_db)
        with open(JSON_PATH, 'wb') as f:
            f.write(original_json)
        remove_path(REPORT_PATH)
        if original_report is not None:
            with open(REPORT_PATH, 'wb') as f:
                f.write(original_report)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
