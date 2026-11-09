#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import uuid

import pytest
from collections import defaultdict, deque

DB_PATH = '/home/user/compliance.db'
AUDIT_PATH = '/home/user/audit.py'
VIOLATIONS_CSV_PATH = '/home/user/violations.csv'


def get_expected_violations():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    # Load edges
    cur.execute("SELECT source, target FROM network_edges")
    adj = defaultdict(list)
    for source, target in cur.fetchall():
        adj[source].append(target)

    # Load employees
    cur.execute("SELECT emp_id, assigned_node FROM employees")
    employees = cur.fetchall()

    # Compute reachable nodes (up to 2 hops)
    reachable = {}
    for emp_id, start_node in employees:
        visited = set()
        queue = deque([(start_node, 0)])
        while queue:
            node, dist = queue.popleft()
            if node not in visited:
                visited.add(node)
                if dist < 2:
                    for neighbor in adj.get(node, []):
                        queue.append((neighbor, dist + 1))
        reachable[emp_id] = visited

    # Check access logs
    cur.execute("SELECT emp_id, accessed_node FROM access_logs")
    logs = cur.fetchall()

    violations = set()
    for emp_id, accessed_node in logs:
        if emp_id in reachable:
            if accessed_node not in reachable[emp_id]:
                violations.add((emp_id, accessed_node))

    conn.close()
    return sorted(list(violations))


def assert_csv_matches(expected_violations):
    assert os.path.exists(VIOLATIONS_CSV_PATH), f"File {VIOLATIONS_CSV_PATH} was not created."
    assert os.path.isfile(VIOLATIONS_CSV_PATH), f"{VIOLATIONS_CSV_PATH} is not a file."

    with open(VIOLATIONS_CSV_PATH, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("The violations.csv file is empty.")

        assert header == ['emp_id', 'accessed_node'], \
            f"Incorrect CSV header. Expected ['emp_id', 'accessed_node'], got {header}."
        rows = list(reader)

    assert len(rows) == len(expected_violations), \
        f"Expected {len(expected_violations)} violation rows, but got {len(rows)}."

    for i, (expected, actual) in enumerate(zip(expected_violations, rows)):
        assert list(expected) == actual, \
            f"Row {i+1} mismatch. Expected {list(expected)}, got {actual}."


def run_audit():
    if os.path.lexists(VIOLATIONS_CSV_PATH):
        os.remove(VIOLATIONS_CSV_PATH)
    result = subprocess.run(
        [sys.executable, AUDIT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, \
        f"audit.py exited with status {result.returncode}. stderr:\n{result.stderr}"


def test_violations_csv_exists():
    assert os.path.exists(VIOLATIONS_CSV_PATH), f"File {VIOLATIONS_CSV_PATH} was not created."
    assert os.path.isfile(VIOLATIONS_CSV_PATH), f"{VIOLATIONS_CSV_PATH} is not a file."


def test_violations_csv_content():
    expected_violations = get_expected_violations()

    with open(VIOLATIONS_CSV_PATH, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("The violations.csv file is empty.")

        assert header == ['emp_id', 'accessed_node'], f"Incorrect CSV header. Expected ['emp_id', 'accessed_node'], got {header}."
        rows = list(reader)

    assert len(rows) == len(expected_violations), f"Expected {len(expected_violations)} violation rows, but got {len(rows)}."

    for i, (expected, actual) in enumerate(zip(expected_violations, rows)):
        assert list(expected) == actual, f"Row {i+1} mismatch. Expected {list(expected)}, got {actual}."


def _static_string(node, assignments):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return assignments.get(node.id)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left = _static_string(node.left, assignments)
        right = _static_string(node.right, assignments)
        if left is not None and right is not None:
            return left + right
    if isinstance(node, ast.JoinedStr):
        return ''.join(
            part.value for part in node.values
            if isinstance(part, ast.Constant) and isinstance(part.value, str)
        )
    return None


def test_audit_script_exists_and_uses_required_database_operations():
    assert os.path.exists(AUDIT_PATH), f"File {AUDIT_PATH} was not created."
    assert os.path.isfile(AUDIT_PATH), f"{AUDIT_PATH} is not a file."

    with open(AUDIT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=AUDIT_PATH)
    except SyntaxError as exc:
        pytest.fail(f"audit.py is not valid Python: {exc}")

    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            value = _static_string(node.value, assignments)
            if value is not None:
                for target in node.targets:
                    if isinstance(target, ast.Name):
                        assignments[target.id] = value

    reads_edges = False
    parameterized_access_logs = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr not in ('execute', 'executemany') or not node.args:
            continue
        query = _static_string(node.args[0], assignments)
        query_lower = query.lower() if query is not None else ''
        if 'network_edges' in query_lower and 'select' in query_lower:
            reads_edges = True
        has_parameters = len(node.args) >= 2 or bool(node.keywords)
        if 'access_logs' in query_lower and has_parameters:
            parameterized_access_logs = True

    assert reads_edges, "audit.py must load network_edges so the graph can be materialized in memory."
    assert parameterized_access_logs, \
        "audit.py must scan access_logs using a parameterized SQLite query."


def test_audit_script_regenerates_original_output():
    expected = get_expected_violations()
    with tempfile.TemporaryDirectory() as tmpdir:
        db_backup = os.path.join(tmpdir, 'compliance.db')
        shutil.copy2(DB_PATH, db_backup)
        try:
            run_audit()
            assert_csv_matches(expected)
        finally:
            for suffix in ('-wal', '-shm'):
                sidecar = DB_PATH + suffix
                if os.path.exists(sidecar):
                    os.remove(sidecar)
            shutil.copy2(db_backup, DB_PATH)


def test_audit_script_on_unseen_database():
    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory() as tmpdir:
        db_backup = os.path.join(tmpdir, 'compliance.db')
        csv_backup = os.path.join(tmpdir, 'violations.csv')
        shutil.copy2(DB_PATH, db_backup)
        had_csv = os.path.isfile(VIOLATIONS_CSV_PATH)
        if had_csv:
            shutil.copy2(VIOLATIONS_CSV_PATH, csv_backup)

        try:
            for suffix in ('', '-wal', '-shm'):
                path = DB_PATH + suffix
                if os.path.exists(path):
                    os.remove(path)

            conn = sqlite3.connect(DB_PATH)
            cur = conn.cursor()
            cur.execute('CREATE TABLE employees (emp_id TEXT, assigned_node TEXT)')
            cur.execute('CREATE TABLE network_edges (source TEXT, target TEXT)')
            cur.execute('CREATE TABLE access_logs (log_id INTEGER, emp_id TEXT, accessed_node TEXT, timestamp TEXT)')

            p = 'P_' + token
            q = 'Q_' + token
            r = 'R_' + token
            nodes = {name: name + '_' + token for name in ('s', 'a', 'b', 'c', 'x', 'q0', 'u', 'v', 'w', 'r0', 'isolated')}

            cur.executemany('INSERT INTO employees VALUES (?, ?)', [
                (p, nodes['s']), (q, nodes['q0']), (r, nodes['r0'])
            ])
            cur.executemany('INSERT INTO network_edges VALUES (?, ?)', [
                (nodes['s'], nodes['a']),
                (nodes['a'], nodes['b']),
                (nodes['b'], nodes['c']),
                (nodes['s'], nodes['x']),
                (nodes['x'], nodes['s']),
                (nodes['q0'], nodes['u']),
                (nodes['q0'], nodes['v']),
                (nodes['u'], nodes['w']),
            ])
            logs = [
                (1, p, nodes['s'], 't1'),
                (2, p, nodes['b'], 't2'),
                (3, p, nodes['c'], 't3'),
                (4, p, nodes['c'], 't4'),
                (5, q, nodes['w'], 't5'),
                (6, q, nodes['a'], 't6'),
                (7, r, nodes['r0'], 't7'),
                (8, r, nodes['isolated'], 't8'),
                (9, 'UNKNOWN_' + token, nodes['isolated'], 't9'),
            ]
            cur.executemany('INSERT INTO access_logs VALUES (?, ?, ?, ?)', logs)
            conn.commit()
            conn.close()

            expected = get_expected_violations()
            run_audit()
            assert_csv_matches(expected)
        finally:
            for suffix in ('', '-wal', '-shm'):
                path = DB_PATH + suffix
                if os.path.exists(path):
                    os.remove(path)
            shutil.copy2(db_backup, DB_PATH)
            if had_csv:
                shutil.copy2(csv_backup, VIOLATIONS_CSV_PATH)
            elif os.path.exists(VIOLATIONS_CSV_PATH):
                os.remove(VIOLATIONS_CSV_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
