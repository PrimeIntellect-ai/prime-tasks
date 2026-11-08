#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import collections
import json
import os
import random
import re
import shutil
import sqlite3
import stat
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_FILE = '/home/user/flatten_bom.py'
OUTPUT_FILE = '/home/user/bom_flattened.json'
DATABASE_FILE = '/home/user/manufacturing.db'


def run_script():
    if os.path.lexists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    result = subprocess.run(
        ['python3', SCRIPT_FILE],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'{SCRIPT_FILE} exited with status {result.returncode}. '
        f'stdout: {result.stdout}\nstderr: {result.stderr}'
    )


def test_script_exists_and_uses_recursive_cte():
    assert os.path.exists(SCRIPT_FILE), f'Required script {SCRIPT_FILE} is missing.'
    mode = os.lstat(SCRIPT_FILE).st_mode
    assert stat.S_ISREG(mode) and not os.path.islink(SCRIPT_FILE), (
        f'{SCRIPT_FILE} must be a regular Python file.'
    )

    with open(SCRIPT_FILE, 'r', encoding='utf-8') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_FILE)
    except SyntaxError as exc:
        pytest.fail(f'{SCRIPT_FILE} is not valid Python: {exc}')

    assignments = collections.defaultdict(list)
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                if isinstance(target, ast.Name):
                    assignments[target.id].append(value)

    def string_values(node, seen=None):
        seen = set() if seen is None else seen
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return [node.value]
        if isinstance(node, ast.Name) and node.id not in seen:
            values = []
            for assigned in assignments.get(node.id, []):
                values.extend(string_values(assigned, seen | {node.id}))
            return values
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
            left = string_values(node.left, seen)
            right = string_values(node.right, seen)
            return [a + b for a in left for b in right]
        if isinstance(node, ast.JoinedStr) and all(
            isinstance(part, ast.Constant) and isinstance(part.value, str)
            for part in node.values
        ):
            return [''.join(part.value for part in node.values)]
        return []

    recursive_sql = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        function_name = ''
        if isinstance(node.func, ast.Attribute):
            function_name = node.func.attr
        elif isinstance(node.func, ast.Name):
            function_name = node.func.id
        if function_name not in {'execute', 'executemany', 'executescript', 'read_sql', 'read_sql_query'}:
            continue
        sql_nodes = list(node.args[:1])
        sql_nodes.extend(kw.value for kw in node.keywords if kw.arg in {'sql', 'query'})
        for sql_node in sql_nodes:
            for sql in string_values(sql_node):
                if re.search(r'\bWITH\s+RECURSIVE\b', sql, flags=re.IGNORECASE) and re.search(
                    r'\bbom\b', sql, flags=re.IGNORECASE
                ):
                    recursive_sql.append(sql)

    assert recursive_sql, (
        'The script must execute an SQL statement using WITH RECURSIVE to traverse the bom table.'
    )


def test_script_runs_on_provided_database():
    run_script()


def test_output_file_exists():
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing. Did you run the script and save the output to the correct path?"
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a file."


def test_output_file_content():
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."

    with open(OUTPUT_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_FILE} does not contain valid JSON.")

    assert isinstance(data, list), "The output JSON must be an array of objects."

    expected_data = [
        {
            "component_id": 2,
            "component_name": "Sub-Assembly A",
            "total_quantity": 2
        },
        {
            "component_id": 3,
            "component_name": "Sub-Assembly B",
            "total_quantity": 1
        },
        {
            "component_id": 4,
            "component_name": "Part C",
            "total_quantity": 6
        },
        {
            "component_id": 5,
            "component_name": "Part D",
            "total_quantity": 10
        },
        {
            "component_id": 6,
            "component_name": "Standard Screw",
            "total_quantity": 62
        }
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} components in the output, but found {len(data)}."

    for i, expected_item in enumerate(expected_data):
        actual_item = data[i]
        assert isinstance(actual_item, dict), f"Item at index {i} is not a JSON object."

        for key in ["component_id", "component_name", "total_quantity"]:
            assert key in actual_item, f"Missing key '{key}' in item at index {i}."
            assert actual_item[key] == expected_item[key], f"Mismatch for '{key}' at index {i}. Expected {expected_item[key]}, got {actual_item[key]}."


def test_script_on_unseen_bom():
    backup_fd, backup_path = tempfile.mkstemp(prefix='manufacturing-backup-', suffix='.db')
    os.close(backup_fd)
    shutil.copy2(DATABASE_FILE, backup_path)

    token = uuid.uuid4().hex[:10]
    rng = random.SystemRandom()
    component_ids = [1, 7, 11, 20, 35, 42, 50]
    names = {1: f'Final Product {token}'}
    for component_id in component_ids[1:]:
        names[component_id] = f'Component {component_id} {token}'

    edges = [
        (1, 7, rng.randint(2, 9)),
        (1, 11, rng.randint(2, 9)),
        (7, 20, rng.randint(2, 9)),
        (7, 35, rng.randint(2, 9)),
        (11, 35, rng.randint(2, 9)),
        (11, 42, rng.randint(2, 9)),
        (20, 42, rng.randint(2, 9)),
        (35, 42, rng.randint(2, 9)),
        (35, 50, rng.randint(2, 9)),
        (42, 50, rng.randint(2, 9)),
    ]

    adjacency = collections.defaultdict(list)
    for parent, child, quantity in edges:
        adjacency[parent].append((child, quantity))
    totals = collections.defaultdict(int)
    stack = [(1, 1)]
    while stack:
        parent, parent_quantity = stack.pop()
        for child, edge_quantity in adjacency[parent]:
            absolute_quantity = parent_quantity * edge_quantity
            totals[child] += absolute_quantity
            stack.append((child, absolute_quantity))

    expected = [
        {
            'component_id': component_id,
            'component_name': names[component_id],
            'total_quantity': totals[component_id],
        }
        for component_id in sorted(totals)
    ]

    try:
        os.remove(DATABASE_FILE)
        conn = sqlite3.connect(DATABASE_FILE)
        try:
            conn.execute('CREATE TABLE components (id INTEGER PRIMARY KEY, name TEXT)')
            conn.execute(
                'CREATE TABLE bom (parent_id INTEGER, child_id INTEGER, quantity INTEGER, '
                'PRIMARY KEY (parent_id, child_id))'
            )
            conn.executemany(
                'INSERT INTO components (id, name) VALUES (?, ?)',
                [(component_id, names[component_id]) for component_id in component_ids]
                + [(99, f'Unreachable {token}')],
            )
            conn.executemany(
                'INSERT INTO bom (parent_id, child_id, quantity) VALUES (?, ?, ?)', edges
            )
            conn.commit()
        finally:
            conn.close()

        run_script()
        assert os.path.isfile(OUTPUT_FILE), 'The script did not create bom_flattened.json.'
        with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
            try:
                actual = json.load(f)
            except json.JSONDecodeError as exc:
                pytest.fail(f'The script produced invalid JSON on an unseen BOM: {exc}')

        assert actual == expected, (
            'The script did not correctly aggregate multiplied quantities across all paths '
            'for an unseen BOM, or the result did not use the required sorted schema.'
        )
        for item in actual:
            assert set(item) == {'component_id', 'component_name', 'total_quantity'}
            assert type(item['component_id']) is int
            assert type(item['component_name']) is str
            assert type(item['total_quantity']) is int
    finally:
        shutil.copy2(backup_path, DATABASE_FILE)
        os.remove(backup_path)
        try:
            run_script()
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
