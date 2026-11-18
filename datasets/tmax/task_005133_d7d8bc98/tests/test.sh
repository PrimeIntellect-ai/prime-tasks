#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_audit_instrumented.py
import re
import runpy
import sqlite3
import sys

script_path = sys.argv[1]
executed_sql = []
original_connect = sqlite3.connect

def traced_connect(*args, **kwargs):
    conn = original_connect(*args, **kwargs)
    conn.set_trace_callback(executed_sql.append)
    return conn

sqlite3.connect = traced_connect
sys.argv = [script_path]
runpy.run_path(script_path, run_name='__main__')

assert any(re.search(r'\bWITH\s+RECURSIVE\b', sql, re.IGNORECASE) for sql in executed_sql), \
    'The script did not execute a recursive CTE'
assert any(re.search(r'\bRANK\s*\(\s*\)\s*OVER\b', sql, re.IGNORECASE) for sql in executed_sql), \
    'The script did not execute a RANK() window function'
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import shutil
import sqlite3
import subprocess
import tempfile
from collections import Counter

import pytest

SCRIPT_PATH = '/home/user/audit_coi.py'
DB_PATH = '/home/user/audit.db'
COI_REPORT_PATH = '/home/user/coi_report.csv'
DEPT_STATS_PATH = '/home/user/dept_stats.csv'
RUNNER_PATH = '/tmp/run_audit_instrumented.py'


def read_nonempty_csv(path):
    with open(path, 'r', newline='', encoding='utf-8') as f:
        return [row for row in csv.reader(f) if any(row)]


def run_submission():
    result = subprocess.run(
        ['python3', RUNNER_PATH, SCRIPT_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        'audit_coi.py failed or did not execute the required SQL features.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def test_script_exists_executes_and_uses_required_sql():
    assert os.path.exists(SCRIPT_PATH), f'Script missing at {SCRIPT_PATH}'
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} is not a regular file'
    run_submission()


def test_coi_report_exists_and_content():
    """Test that coi_report.csv exists and contains the correct data."""
    assert os.path.exists(COI_REPORT_PATH), f"Report file missing at {COI_REPORT_PATH}"
    assert os.path.isfile(COI_REPORT_PATH), f"{COI_REPORT_PATH} is not a file"

    expected_rows = [
        ['emp_id', 'department'],
        ['1', 'Executive'],
        ['6', 'SpecialOps'],
        ['7', 'IT'],
        ['8', 'IT']
    ]

    with open(COI_REPORT_PATH, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        actual_rows = [row for row in reader if any(row)]  # ignore empty lines

    assert actual_rows == expected_rows, f"Content of {COI_REPORT_PATH} does not match expected output.\nExpected: {expected_rows}\nActual: {actual_rows}"


def test_dept_stats_exists_and_content():
    """Test that dept_stats.csv exists and contains the correct data."""
    assert os.path.exists(DEPT_STATS_PATH), f"Report file missing at {DEPT_STATS_PATH}"
    assert os.path.isfile(DEPT_STATS_PATH), f"{DEPT_STATS_PATH} is not a file"

    expected_rows = [
        ['department', 'coi_count', 'dept_rank'],
        ['IT', '2', '1'],
        ['Executive', '1', '2'],
        ['SpecialOps', '1', '2']
    ]

    with open(DEPT_STATS_PATH, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        actual_rows = [row for row in reader if any(row)]  # ignore empty lines

    assert actual_rows == expected_rows, f"Content of {DEPT_STATS_PATH} does not match expected output.\nExpected: {expected_rows}\nActual: {actual_rows}"


def test_z_submission_handles_unseen_database():
    rng = random.SystemRandom()
    parent_indexes = [None, 0, 0, 1, 3, 2, 2, 5, 7, 0, 9, 10, 4, 11]
    n = len(parent_indexes)
    ids = rng.sample(range(1000, 9000), n)
    dept_names = [f'Dept_{rng.randrange(100000, 999999)}' for _ in range(5)]
    rng.shuffle(dept_names)

    employees = []
    for i, parent_index in enumerate(parent_indexes):
        manager_id = None if parent_index is None else ids[parent_index]
        employees.append((ids[i], f'Employee {i}', manager_id, dept_names[i % len(dept_names)]))

    access = set()
    # Split access across deep descendants, plus a direct conflict, so direct-only
    # and one-level hierarchy implementations cannot pass.
    access.update({
        (ids[4], 101), (ids[3], 202),
        (ids[6], 101), (ids[8], 202),
        (ids[10], 101), (ids[10], 202),
        (ids[13], 303),
    })
    for emp_id in ids:
        if rng.random() < 0.18:
            access.add((emp_id, 101))
        if rng.random() < 0.18:
            access.add((emp_id, 202))
        if rng.random() < 0.20:
            access.add((emp_id, 303))

    children = {emp_id: [] for emp_id in ids}
    departments = {}
    for emp_id, _name, manager_id, department in employees:
        departments[emp_id] = department
        if manager_id is not None:
            children[manager_id].append(emp_id)

    direct = {emp_id: set() for emp_id in ids}
    for emp_id, sys_id in access:
        direct[emp_id].add(sys_id)

    def inherited_systems(emp_id):
        systems = set()
        stack = [emp_id]
        while stack:
            current = stack.pop()
            systems.update(direct[current])
            stack.extend(children[current])
        return systems

    violating_ids = sorted(
        emp_id for emp_id in ids
        if {101, 202}.issubset(inherited_systems(emp_id))
    )
    expected_coi = [['emp_id', 'department']] + [
        [str(emp_id), departments[emp_id]] for emp_id in violating_ids
    ]

    counts = Counter(departments[emp_id] for emp_id in violating_ids)
    ranked = []
    for department, count in counts.items():
        rank = 1 + sum(1 for other_count in counts.values() if other_count > count)
        ranked.append((rank, department, count))
    ranked.sort(key=lambda row: (row[0], row[1]))
    expected_stats = [['department', 'coi_count', 'dept_rank']] + [
        [department, str(count), str(rank)] for rank, department, count in ranked
    ]

    backup_dir = tempfile.mkdtemp(prefix='audit-verifier-')
    db_backup = os.path.join(backup_dir, 'audit.db')
    coi_backup = os.path.join(backup_dir, 'coi_report.csv')
    stats_backup = os.path.join(backup_dir, 'dept_stats.csv')
    shutil.copy2(DB_PATH, db_backup)
    if os.path.exists(COI_REPORT_PATH):
        shutil.copy2(COI_REPORT_PATH, coi_backup)
    if os.path.exists(DEPT_STATS_PATH):
        shutil.copy2(DEPT_STATS_PATH, stats_backup)

    try:
        for suffix in ('', '-wal', '-shm', '-journal'):
            path = DB_PATH + suffix
            if os.path.exists(path):
                os.remove(path)

        conn = sqlite3.connect(DB_PATH)
        conn.execute('CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, department TEXT)')
        conn.execute('CREATE TABLE systems (sys_id INTEGER PRIMARY KEY, sys_name TEXT, sensitivity_level INTEGER)')
        conn.execute('CREATE TABLE direct_access (emp_id INTEGER, sys_id INTEGER)')
        conn.executemany('INSERT INTO employees VALUES (?,?,?,?)', employees)
        conn.executemany('INSERT INTO systems VALUES (?,?,?)', [
            (101, 'Trading Platform', 5),
            (202, 'Audit Platform', 5),
            (303, 'Email', 1),
        ])
        conn.executemany('INSERT INTO direct_access VALUES (?,?)', sorted(access))
        conn.commit()
        conn.close()

        run_submission()

        assert os.path.isfile(COI_REPORT_PATH), 'Dynamic CoI report was not generated'
        assert os.path.isfile(DEPT_STATS_PATH), 'Dynamic department report was not generated'
        actual_coi = read_nonempty_csv(COI_REPORT_PATH)
        actual_stats = read_nonempty_csv(DEPT_STATS_PATH)
        assert actual_coi == expected_coi, (
            f'Incorrect report for unseen database.\nExpected: {expected_coi}\nActual: {actual_coi}'
        )
        assert actual_stats == expected_stats, (
            f'Incorrect department statistics for unseen database.\n'
            f'Expected: {expected_stats}\nActual: {actual_stats}'
        )
    finally:
        for suffix in ('', '-wal', '-shm', '-journal'):
            path = DB_PATH + suffix
            if os.path.exists(path):
                os.remove(path)
        shutil.copy2(db_backup, DB_PATH)
        if os.path.exists(coi_backup):
            shutil.copy2(coi_backup, COI_REPORT_PATH)
        if os.path.exists(stats_backup):
            shutil.copy2(stats_backup, DEPT_STATS_PATH)
        shutil.rmtree(backup_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
