#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/verifier_instrument

cat << 'PY_EOF' > /tmp/verifier_instrument/sitecustomize.py
import json
import os
import sqlite3

_original_connect = sqlite3.connect
_trace_path = os.environ.get("SQL_TRACE_PATH")

def _connect(*args, **kwargs):
    conn = _original_connect(*args, **kwargs)
    if _trace_path:
        def record(statement):
            with open(_trace_path, "a", encoding="utf-8") as trace_file:
                trace_file.write(json.dumps(statement) + "\n")
        conn.set_trace_callback(record)
    return conn

sqlite3.connect = _connect
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

DB_PATH = '/home/user/audit.db'
SCRIPT_PATH = '/home/user/generate_report.py'
JSON_PATH = '/home/user/compliance_graph.json'
TRACE_PATH = '/tmp/generate_report_sql_trace.jsonl'
INSTRUMENT_PATH = '/tmp/verifier_instrument'


def get_expected_data(db_path=DB_PATH):
    assert os.path.exists(db_path), f"Database file {db_path} is missing."

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("SELECT emp_id, name, manager_id, dept_id FROM employees")
    employees = cur.fetchall()

    cur.execute("SELECT dept_id, resource FROM permissions")
    permissions = dict(cur.fetchall())

    conn.close()

    emp_dict = {row[0]: row for row in employees}

    def get_path(emp_id):
        path = []
        curr = emp_id
        visited = set()
        while curr is not None and curr not in visited:
            visited.add(curr)
            path.insert(0, str(curr))
            curr = emp_dict[curr][2]
        return "->".join(path)

    expected = []
    for emp_id, name, manager_id, dept_id in employees:
        expected.append({
            "emp_id": emp_id,
            "name": name,
            "resource": permissions.get(dept_id),
            "path": get_path(emp_id)
        })

    expected.sort(key=lambda x: x["emp_id"])
    return expected


def assert_json_matches(expected_data):
    assert os.path.exists(JSON_PATH), f"The output file {JSON_PATH} does not exist."
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} is not a file."

    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_PATH} does not contain valid JSON.")

    assert isinstance(data, list), "The JSON root must be a list of dictionaries."
    assert len(data) == len(expected_data), (
        f"Expected {len(expected_data)} records, but found {len(data)}."
    )

    emp_ids = [row.get("emp_id") for row in data]
    assert emp_ids == sorted(emp_ids), (
        "The JSON array is not sorted in ascending order by emp_id."
    )

    for i, (actual_row, expected_row) in enumerate(zip(data, expected_data)):
        assert isinstance(actual_row, dict), f"Item at index {i} is not a dictionary."
        for key in ["emp_id", "name", "resource", "path"]:
            assert key in actual_row, f"Missing key '{key}' in item at index {i}."
            assert actual_row[key] == expected_row[key], (
                f"Mismatch at index {i} for key '{key}': "
                f"expected {expected_row[key]}, got {actual_row[key]}."
            )


def run_script_with_trace():
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)

    env = os.environ.copy()
    old_path = env.get('PYTHONPATH', '')
    env['PYTHONPATH'] = INSTRUMENT_PATH + (os.pathsep + old_path if old_path else '')
    env['SQL_TRACE_PATH'] = TRACE_PATH

    completed = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, (
        "generate_report.py failed when executed.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def create_challenge_database(path):
    if os.path.exists(path):
        os.remove(path)
    conn = sqlite3.connect(path)
    cur = conn.cursor()
    cur.execute('CREATE TABLE employees (emp_id INT, name TEXT, manager_id INT, dept_id INT)')
    cur.execute('CREATE TABLE permissions (dept_id INT, resource TEXT)')
    cur.executemany('INSERT INTO employees VALUES (?, ?, ?, ?)', [
        (305, 'Nested Analyst', 77, 900),
        (42, 'Challenge CEO', None, 700),
        (901, 'Remote Intern', 305, 900),
        (77, 'Operations Director', 42, 800),
        (18, 'Security Lead', 42, 900),
        (640, 'Field Operator', 77, 800),
    ])
    cur.executemany('INSERT INTO permissions VALUES (?, ?)', [
        (700, 'Executive Console'),
        (800, 'Operations Grid'),
        (900, 'Security Vault'),
        (999, 'Unassigned Decoy'),
    ])
    conn.commit()
    conn.close()


def load_recursive_statements():
    assert os.path.isfile(TRACE_PATH), (
        "The script did not execute any instrumented SQLite operations."
    )
    statements = []
    with open(TRACE_PATH, 'r', encoding='utf-8') as trace_file:
        for line in trace_file:
            if line.strip():
                statement = json.loads(line)
                if re.search(r'\bWITH\s+RECURSIVE\b', statement, re.IGNORECASE):
                    statements.append(statement)
    assert statements, (
        "generate_report.py did not execute an SQL statement using WITH RECURSIVE."
    )
    return statements


def assert_recursive_query_produces_report(statements, challenge_db, expected):
    required = ['emp_id', 'name', 'resource', 'path']
    expected_rows = [tuple(row[key] for key in required) for row in expected]
    expected_rows.sort(key=lambda row: row[0])

    for statement in statements:
        query_copy = tempfile.NamedTemporaryFile(suffix='.db', delete=False)
        query_copy.close()
        shutil.copy2(challenge_db, query_copy.name)
        try:
            conn = sqlite3.connect(query_copy.name)
            try:
                cur = conn.cursor()
                cur.execute(statement)
                if cur.description is None:
                    continue
                names = [column[0].lower() for column in cur.description]
                if not all(key in names for key in required):
                    continue
                indexes = [names.index(key) for key in required]
                rows = [tuple(row[index] for index in indexes) for row in cur.fetchall()]
                rows.sort(key=lambda row: row[0])
                if rows == expected_rows:
                    return
            except sqlite3.Error:
                pass
            finally:
                conn.close()
        finally:
            os.remove(query_copy.name)

    pytest.fail(
        "No executed WITH RECURSIVE query itself produced the required hierarchy, "
        "department-specific resource join, and path values."
    )


def test_compliance_graph_json_and_recursive_sql():
    assert os.path.exists(SCRIPT_PATH), f"The required script {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file."
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    original_backup = tempfile.NamedTemporaryFile(suffix='.db', delete=False)
    original_backup.close()
    shutil.copy2(DB_PATH, original_backup.name)
    original_expected = get_expected_data(original_backup.name)

    challenge_backup = tempfile.NamedTemporaryFile(suffix='.db', delete=False)
    challenge_backup.close()

    try:
        # Execute the submitted artifact on the supplied database, then retain all
        # of the original verifier's JSON assertions.
        run_script_with_trace()
        shutil.copy2(original_backup.name, DB_PATH)
        assert_json_matches(original_expected)

        # Exercise the same script on independently chosen hierarchy data so a
        # precomputed report cannot pass.
        create_challenge_database(DB_PATH)
        shutil.copy2(DB_PATH, challenge_backup.name)
        challenge_expected = get_expected_data(challenge_backup.name)
        run_script_with_trace()

        # Restore the challenge database if the submission changed it before
        # checking both its output and the actual SQL statements it executed.
        shutil.copy2(challenge_backup.name, DB_PATH)
        assert_json_matches(challenge_expected)
        recursive_statements = load_recursive_statements()
        assert_recursive_query_produces_report(
            recursive_statements, challenge_backup.name, challenge_expected
        )

        # Leave the requested report generated from the original supplied DB.
        shutil.copy2(original_backup.name, DB_PATH)
        run_script_with_trace()
        shutil.copy2(original_backup.name, DB_PATH)
        assert_json_matches(original_expected)
    finally:
        shutil.copy2(original_backup.name, DB_PATH)
        os.remove(original_backup.name)
        os.remove(challenge_backup.name)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
