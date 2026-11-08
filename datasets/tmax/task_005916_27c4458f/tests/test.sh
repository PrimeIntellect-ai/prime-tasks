#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import ast
import csv
import json
import os
import random
import re
import sqlite3
import stat
import subprocess
import sys
import uuid

SCRIPT = '/home/user/generate_report.py'
REPORT = '/home/user/task_report.csv'
DB = '/home/user/data/org.db'
TASKS = '/home/user/data/tasks.json'


def run_script():
    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'generate_report.py exited with status {result.returncode}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )
    assert os.path.isfile(REPORT), f'The report file {REPORT} does not exist.'


def read_rows():
    assert os.path.isfile(REPORT), f'The report file {REPORT} does not exist.'
    with open(REPORT, 'r', newline='', encoding='utf-8') as f:
        rows = list(csv.reader(f))
    assert len(rows) > 0, 'The CSV file is empty.'
    expected_header = ['employee_id', 'employee_name', 'total_tasks']
    assert rows[0] == expected_header, (
        f'CSV header is incorrect. Expected {expected_header}, got {rows[0]}.'
    )
    return rows


def check_source_requirements():
    assert os.path.exists(SCRIPT), f'The required script {SCRIPT} does not exist.'
    mode = os.lstat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f'{SCRIPT} must be a regular Python file.'

    with open(SCRIPT, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)

    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    assignments[target.id] = node.value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            assignments[node.target.id] = node.value

    def static_string(node, seen=None):
        seen = set() if seen is None else seen
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
            left = static_string(node.left, seen)
            right = static_string(node.right, seen)
            return None if left is None or right is None else left + right
        if isinstance(node, ast.JoinedStr) and all(isinstance(v, ast.Constant) and isinstance(v.value, str) for v in node.values):
            return ''.join(v.value for v in node.values)
        if isinstance(node, ast.Name) and node.id not in seen and node.id in assignments:
            return static_string(assignments[node.id], seen | {node.id})
        return None

    recursive_cte = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not node.args:
            continue
        if not isinstance(node.func, ast.Attribute) or node.func.attr not in {'execute', 'executemany', 'executescript'}:
            continue
        query = static_string(node.args[0])
        if query is not None and re.search(r'\bWITH\s+RECURSIVE\b', query, re.IGNORECASE):
            recursive_cte = True
            break
    assert recursive_cte, 'The script must execute an SQLite query using WITH RECURSIVE.'

    recursive_parser = False
    for fn in (n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))):
        for node in ast.walk(fn):
            if not isinstance(node, ast.Call):
                continue
            if isinstance(node.func, ast.Name) and node.func.id == fn.name:
                recursive_parser = True
                break
            if isinstance(node.func, ast.Attribute) and node.func.attr == fn.name:
                recursive_parser = True
                break
        if recursive_parser:
            break
    assert recursive_parser, 'The script must use recursive Python traversal for nested tasks/subtasks.'


def check_original_fixture():
    run_script()
    rows = read_rows()
    data_rows = rows[1:]
    expected_data = [
        ['5', 'Eve', '2'],
        ['1', 'Alice', '1'],
        ['2', 'Bob', '1'],
        ['3', 'Charlie', '1'],
        ['4', 'Dave', '1'],
        ['6', 'Frank', '0'],
    ]
    assert len(data_rows) == len(expected_data), (
        f'Expected {len(expected_data)} data rows, but got {len(data_rows)}.'
    )
    for i, (actual, expected) in enumerate(zip(data_rows, expected_data)):
        assert actual == expected, f'Row {i + 1} is incorrect. Expected {expected}, got {actual}.'

    with open(REPORT, 'r', newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            employee_id = int(row['employee_id'])
            assert employee_id not in [7, 8], (
                f'Employee {employee_id} should not be in the report as they are not in the CEO hierarchy.'
            )


def make_dynamic_fixture():
    rng = random.SystemRandom()
    chosen = rng.sample(range(100, 1000000), 12)
    hierarchy_ids = [1] + chosen[:9]
    outsider_id, outsider_child_id, unused_id = chosen[9:12]

    employees = [(1, 'CEO_' + uuid.uuid4().hex, None)]
    for index, employee_id in enumerate(hierarchy_ids[1:], 1):
        parent = hierarchy_ids[index - 1]
        employees.append((employee_id, 'Employee_' + uuid.uuid4().hex, parent))
    employees.extend([
        (outsider_id, 'Outsider_' + uuid.uuid4().hex, None),
        (outsider_child_id, 'OutsideChild_' + uuid.uuid4().hex, outsider_id),
        (unused_id, 'Unused_' + uuid.uuid4().hex, None),
    ])

    assignees = [
        hierarchy_ids[2], hierarchy_ids[1], outsider_id, hierarchy_ids[2],
        hierarchy_ids[5], hierarchy_ids[1], hierarchy_ids[7], outsider_child_id,
        hierarchy_ids[5], hierarchy_ids[8], hierarchy_ids[2], hierarchy_ids[4],
        hierarchy_ids[8], hierarchy_ids[1],
    ]
    nested = None
    for depth, assignee in reversed(list(enumerate(assignees))):
        nested = {
            'id': f'deep-{depth}-{uuid.uuid4().hex}',
            'assignee': assignee,
            'subtasks': [] if nested is None else [nested],
        }
    tasks = [
        nested,
        {'id': 'root-' + uuid.uuid4().hex, 'assignee': 1, 'subtasks': []},
        {'id': 'outside-' + uuid.uuid4().hex, 'assignee': outsider_id, 'subtasks': []},
    ]

    if os.path.exists(DB):
        os.remove(DB)
    conn = sqlite3.connect(DB)
    try:
        conn.execute('CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER)')
        conn.executemany('INSERT INTO employees (id, name, manager_id) VALUES (?, ?, ?)', employees)
        conn.commit()
    finally:
        conn.close()
    with open(TASKS, 'w', encoding='utf-8') as f:
        json.dump(tasks, f)


def derive_expected():
    conn = sqlite3.connect(DB)
    try:
        employees = conn.execute('SELECT id, name, manager_id FROM employees').fetchall()
    finally:
        conn.close()

    by_manager = {}
    names = {}
    for employee_id, name, manager_id in employees:
        names[employee_id] = name
        by_manager.setdefault(manager_id, []).append(employee_id)

    hierarchy = set()
    pending = [1]
    while pending:
        employee_id = pending.pop()
        if employee_id in hierarchy:
            continue
        hierarchy.add(employee_id)
        pending.extend(by_manager.get(employee_id, []))

    with open(TASKS, 'r', encoding='utf-8') as f:
        tasks = json.load(f)
    counts = {employee_id: 0 for employee_id in hierarchy}

    def visit(nodes):
        for task in nodes:
            assignee = task['assignee']
            if assignee in counts:
                counts[assignee] += 1
            visit(task.get('subtasks', []))

    visit(tasks)
    ordered = sorted(hierarchy, key=lambda employee_id: (-counts[employee_id], employee_id))
    return [[str(employee_id), names[employee_id], str(counts[employee_id])] for employee_id in ordered]


def check_dynamic_fixture():
    make_dynamic_fixture()
    expected = derive_expected()
    run_script()
    rows = read_rows()
    actual = rows[1:]
    assert len(actual) == len(expected), (
        f'Dynamic fixture expected {len(expected)} data rows, but got {len(actual)}.'
    )
    assert actual == expected, f'Dynamic fixture output is incorrect. Expected {expected}, got {actual}.'


check_source_requirements()
check_original_fixture()

with open(DB, 'rb') as f:
    original_db = f.read()
with open(TASKS, 'rb') as f:
    original_tasks = f.read()
with open(REPORT, 'rb') as f:
    original_report = f.read()

try:
    check_dynamic_fixture()
finally:
    with open(DB, 'wb') as f:
        f.write(original_db)
    with open(TASKS, 'wb') as f:
        f.write(original_tasks)
    with open(REPORT, 'wb') as f:
        f.write(original_report)
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
