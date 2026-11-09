#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

OUTPUT_JSON_PATH = '/home/user/department_summary.json'
SCRIPT_PATH = '/home/user/etl_pipeline.py'
DB_PATH = '/home/user/legacy_corp.db'


def run_pipeline():
    if os.path.exists(OUTPUT_JSON_PATH):
        os.remove(OUTPUT_JSON_PATH)
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'ETL script failed with exit code {result.returncode}. '
        f'stdout: {result.stdout}\nstderr: {result.stderr}'
    )
    assert os.path.isfile(OUTPUT_JSON_PATH), (
        f'Running {SCRIPT_PATH} did not create {OUTPUT_JSON_PATH}'
    )


@pytest.fixture(scope='session', autouse=True)
def execute_and_restore_database():
    fd, backup_path = tempfile.mkstemp(prefix='legacy_corp_', suffix='.db')
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)
    run_pipeline()
    try:
        yield
    finally:
        for suffix in ('-wal', '-shm'):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)


def test_script_exists():
    """Test that the ETL pipeline script exists."""
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file"


def test_script_uses_parameterized_database_call():
    """Require a SQLite execution call whose SQL contains bound placeholders."""
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()

    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f'ETL script is not valid Python: {exc}')

    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    assignments[target.id] = node.value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            assignments[node.target.id] = node.value

    placeholder_re = re.compile(r'\?|[:@$][A-Za-z_]\w*')

    def has_placeholder(expr, seen=None):
        if expr is None:
            return False
        seen = set() if seen is None else seen
        if isinstance(expr, ast.Name) and expr.id in assignments and expr.id not in seen:
            return has_placeholder(assignments[expr.id], seen | {expr.id})
        for child in ast.walk(expr):
            if isinstance(child, ast.Constant) and isinstance(child.value, str):
                if placeholder_re.search(child.value):
                    return True
        return False

    parameterized = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr not in ('execute', 'executemany'):
            continue
        supplies_parameters = len(node.args) >= 2 or any(
            kw.arg in ('parameters', 'params') for kw in node.keywords
        )
        if supplies_parameters and node.args and has_placeholder(node.args[0]):
            parameterized = True
            break

    assert parameterized, (
        'The ETL script must execute a SQL statement using placeholders and a '
        'separate parameter collection.'
    )


def test_output_json_exists_and_valid():
    """Test that the output JSON file exists and contains valid JSON."""
    assert os.path.exists(OUTPUT_JSON_PATH), f"Output JSON not found at {OUTPUT_JSON_PATH}"
    assert os.path.isfile(OUTPUT_JSON_PATH), f"Path {OUTPUT_JSON_PATH} is not a file"

    with open(OUTPUT_JSON_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_JSON_PATH} does not contain valid JSON")

    assert isinstance(data, dict), "The JSON output must be a single JSON object (dictionary)"


def test_output_json_content():
    """Test that the output JSON contains the correct aggregated data and keys are sorted."""
    with open(OUTPUT_JSON_PATH, 'r') as f:
        data = json.load(f)

    expected_data = {
        "PRJ-A": 35,
        "PRJ-B": 45,
        "PRJ-C": 5
    }

    assert data == expected_data, f"JSON content does not match expected output. Got: {data}"

    # Check if keys are sorted alphabetically
    keys = list(data.keys())
    assert keys == sorted(keys), "The keys in the JSON object are not sorted alphabetically"


def test_pipeline_recomputes_from_database_and_follows_deep_hierarchy():
    """Change the database, rerun the artifact, and independently derive its answer."""
    conn = sqlite3.connect(DB_PATH)
    try:
        cur = conn.cursor()
        cur.execute('UPDATE tbl_metric_log SET duration_hrs = ? WHERE log_seq = ?', (13, 1))
        cur.executemany(
            'INSERT INTO tbl_node_ref(id_hash, parent_hash, title, full_moniker) VALUES (?, ?, ?, ?)',
            [
                (9001, 4, 'IC', 'Deep Report One'),
                (9002, 9001, 'IC', 'Deep Report Two'),
                (9003, 6, 'IC', 'Unrelated Report'),
            ],
        )
        cur.executemany(
            'INSERT INTO tbl_metric_log(log_seq, actor_hash, job_code, duration_hrs) VALUES (?, ?, ?, ?)',
            [
                (9001, 9001, 'PRJ-AA', 7),
                (9002, 9002, 'PRJ-DEEP', 11),
                (9003, 9002, 'PRJ-A', 2),
                (9004, 9003, 'PRJ-DEEP', 999),
            ],
        )
        conn.commit()

        rows = cur.execute(
            'SELECT id_hash, parent_hash, full_moniker FROM tbl_node_ref'
        ).fetchall()
        manager_ids = [row[0] for row in rows if row[2] == 'Eleanor Vance']
        assert len(manager_ids) == 1

        children = {}
        for employee_id, parent_id, _ in rows:
            children.setdefault(parent_id, []).append(employee_id)

        subtree = set()
        pending = list(manager_ids)
        while pending:
            employee_id = pending.pop()
            if employee_id in subtree:
                continue
            subtree.add(employee_id)
            pending.extend(children.get(employee_id, []))

        expected = {}
        for actor_id, project, hours in cur.execute(
            'SELECT actor_hash, job_code, duration_hrs FROM tbl_metric_log'
        ):
            if actor_id in subtree:
                expected[project] = expected.get(project, 0) + hours
        expected = dict(sorted(expected.items()))
    finally:
        conn.close()

    run_pipeline()
    with open(OUTPUT_JSON_PATH, 'r', encoding='utf-8') as f:
        actual = json.load(f)

    assert actual == expected, (
        'The script did not recompute the department summary from the modified '
        f'database. Expected {expected}, got {actual}'
    )
    assert list(actual.keys()) == sorted(actual.keys()), 'Output keys are not sorted alphabetically'
    assert all(type(value) is int for value in actual.values()), 'All totals must be integers'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
