#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import sqlite3
import stat
import subprocess
import sys
import tempfile

SCRIPT_PATH = '/home/user/audit_access.py'
CSV_PATH = '/home/user/zeus_audit.csv'


def read_csv(path):
    with open(path, 'r', newline='') as f:
        reader = csv.reader(f)
        return [[cell.strip() for cell in row] for row in reader if row]


def run_script(cwd):
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'audit_access.py exited with status {result.returncode}. '
        f'stdout: {result.stdout!r}; stderr: {result.stderr!r}'
    )


def test_script_exists_and_generates_required_output():
    assert os.path.exists(SCRIPT_PATH), f'{SCRIPT_PATH} does not exist.'
    assert stat.S_ISREG(os.lstat(SCRIPT_PATH).st_mode), f'{SCRIPT_PATH} is not a regular file.'

    if os.path.lexists(CSV_PATH):
        os.remove(CSV_PATH)
    run_script('/home/user')


def test_zeus_audit_csv_exists():
    csv_path = '/home/user/zeus_audit.csv'
    assert os.path.exists(csv_path), f'The output file {csv_path} does not exist. Did you run the script?'
    assert os.path.isfile(csv_path), f'{csv_path} is not a regular file.'


def test_zeus_audit_csv_contents():
    csv_path = '/home/user/zeus_audit.csv'
    assert os.path.exists(csv_path), f'Cannot check contents, {csv_path} is missing.'

    rows = read_csv(csv_path)
    expected_rows = [
        ['employee_name', 'system_name'],
        ['Alice', 'Project_Zeus'],
        ['Bob', 'Project_Zeus'],
        ['Dave', 'Project_Zeus']
    ]

    assert rows == expected_rows, (
        f'Contents of {csv_path} do not match the expected hierarchical access graph. '
        f'Expected {expected_rows}, but got {rows}.'
    )


def make_case(directory, seed):
    rng = random.Random(seed)
    count = 10
    ids = rng.sample(range(100, 10000), count)
    token = secrets.token_hex(5)
    names = [f'Employee_{token}_{i}_{rng.randrange(10000, 99999)}' for i in range(count)]

    # Build a randomized acyclic hierarchy. Each employee after the first has
    # exactly one manager chosen from employees appearing earlier in the list.
    parents = {}
    edges = []
    for child_index in range(1, count):
        parent_index = rng.randrange(0, child_index)
        parents[ids[child_index]] = ids[parent_index]
        edges.append((ids[parent_index], ids[child_index]))

    # Give Zeus access to non-root employees so both direct and inherited access
    # must be reported, while employees in unrelated branches must be excluded.
    direct_ids = {ids[count - 1], ids[count - 2]}

    expected_ids = set(direct_ids)
    for employee_id in direct_ids:
        current = employee_id
        while current in parents:
            current = parents[current]
            expected_ids.add(current)

    db_path = os.path.join(directory, 'compliance.db')
    conn = sqlite3.connect(db_path)
    conn.executescript('''
        CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT);
        CREATE TABLE hierarchy (manager_id INTEGER, employee_id INTEGER);
        CREATE TABLE roles (id INTEGER PRIMARY KEY, name TEXT);
        CREATE TABLE employee_roles (emp_id INTEGER, role_id INTEGER);
        CREATE TABLE system_access (role_id INTEGER, system_name TEXT);
    ''')
    conn.executemany('INSERT INTO employees VALUES (?, ?)', zip(ids, names))
    conn.executemany('INSERT INTO hierarchy VALUES (?, ?)', edges)
    conn.executemany('INSERT INTO roles VALUES (?, ?)', [(31, 'General'), (47, 'Zeus_Operator')])
    conn.executemany('INSERT INTO employee_roles VALUES (?, ?)', [(employee_id, 31) for employee_id in ids])
    conn.executemany('INSERT INTO employee_roles VALUES (?, ?)', [(employee_id, 47) for employee_id in direct_ids])
    conn.executemany('INSERT INTO system_access VALUES (?, ?)', [(31, 'Email'), (47, 'Project_Zeus')])
    conn.commit()
    conn.close()

    name_by_id = dict(zip(ids, names))
    return [
        ['employee_name', 'system_name'],
        *[[name, 'Project_Zeus'] for name in sorted(name_by_id[i] for i in expected_ids)]
    ]


def test_script_computes_hierarchy_on_fresh_databases():
    for _ in range(3):
        with tempfile.TemporaryDirectory() as directory:
            expected = make_case(directory, secrets.randbits(64))
            run_script(directory)
            output_path = os.path.join(directory, 'zeus_audit.csv')
            assert os.path.isfile(output_path), 'The script did not create zeus_audit.csv on a fresh database.'
            actual = read_csv(output_path)
            assert actual == expected, (
                'audit_access.py did not compute the true manager-to-subordinate '
                f'access graph. Expected {expected}, but got {actual}.'
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
