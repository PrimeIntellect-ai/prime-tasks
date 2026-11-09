#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import runpy
import secrets
import shutil
import sqlite3
import subprocess
import sys
from unittest import mock

import pytest

SCRIPT_PATH = '/home/user/graph_etl.py'
DB_PATH = '/home/user/company.db'
OUTPUT_FILE_2 = '/home/user/output_depth_2.json'
OUTPUT_FILE_3 = '/home/user/output_depth_3.json'


def test_script_exists():
    """Check if the required Python script exists."""
    assert os.path.exists(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file"


def test_output_file_2_exists_and_correct():
    """Check if the output file for depth 2 exists and has the correct JSON content."""
    assert os.path.exists(OUTPUT_FILE_2), f"Output file missing at {OUTPUT_FILE_2}"

    with open(OUTPUT_FILE_2, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_FILE_2} is not valid JSON")

    assert "target_depth" in data, "Key 'target_depth' missing in JSON"
    assert data["target_depth"] == 2, f"Expected target_depth to be 2, got {data['target_depth']}"

    assert "employees" in data, "Key 'employees' missing in JSON"
    expected_employees = ["Tom", "Uma", "Victor", "Wendy"]
    assert data["employees"] == expected_employees, f"Expected employees {expected_employees}, got {data['employees']}"


def test_script_works_for_other_depths():
    """Run the script for depth 3 to verify it uses the command-line argument and processes correctly."""
    assert os.path.exists(SCRIPT_PATH), f"Cannot run test, script missing at {SCRIPT_PATH}"

    result = subprocess.run(['python3', SCRIPT_PATH, '3'], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed when run for depth 3. Stderr: {result.stderr}"

    assert os.path.exists(OUTPUT_FILE_3), f"Output file missing at {OUTPUT_FILE_3} after running script for depth 3"

    with open(OUTPUT_FILE_3, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_FILE_3} is not valid JSON")

    assert data.get("target_depth") == 3, f"Expected target_depth 3, got {data.get('target_depth')}"
    expected_employees = ["Rachel", "Sarah"]
    assert data.get("employees") == expected_employees, f"Expected employees {expected_employees}, got {data.get('employees')}"


class TracedCursor:
    def __init__(self, inner, statements):
        self._inner = inner
        self._statements = statements

    def execute(self, sql, parameters=()):
        self._statements.append((sql, parameters))
        self._inner.execute(sql, parameters)
        return self

    def executemany(self, sql, parameters):
        self._statements.append((sql, parameters))
        self._inner.executemany(sql, parameters)
        return self

    def __iter__(self):
        return iter(self._inner)

    def __getattr__(self, name):
        return getattr(self._inner, name)


class TracedConnection:
    def __init__(self, inner, statements):
        object.__setattr__(self, '_inner', inner)
        object.__setattr__(self, '_statements', statements)

    def cursor(self, *args, **kwargs):
        return TracedCursor(self._inner.cursor(*args, **kwargs), self._statements)

    def execute(self, sql, parameters=()):
        self._statements.append((sql, parameters))
        return TracedCursor(self._inner.execute(sql, parameters), self._statements)

    def __enter__(self):
        self._inner.__enter__()
        return self

    def __exit__(self, *args):
        return self._inner.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._inner, name)

    def __setattr__(self, name, value):
        if name in {'_inner', '_statements'}:
            object.__setattr__(self, name, value)
        else:
            setattr(self._inner, name, value)


def _parameter_contains(parameters, target):
    if isinstance(parameters, dict):
        values = parameters.values()
    elif isinstance(parameters, (tuple, list)):
        values = parameters
    else:
        values = [parameters]
    return any(value == target for value in values)


def _run_with_sql_trace(target):
    statements = []
    real_connect = sqlite3.connect

    def traced_connect(*args, **kwargs):
        return TracedConnection(real_connect(*args, **kwargs), statements)

    old_argv = sys.argv[:]
    try:
        sys.argv = [SCRIPT_PATH, str(target)]
        with mock.patch.object(sqlite3, 'connect', traced_connect):
            try:
                runpy.run_path(SCRIPT_PATH, run_name='__main__')
            except SystemExit as exc:
                assert exc.code in (None, 0), f"Script exited unsuccessfully for depth {target}: {exc.code}"
    finally:
        sys.argv = old_argv

    matching = []
    for sql, parameters in statements:
        if not isinstance(sql, str):
            continue
        normalized = ' '.join(sql.upper().split())
        has_placeholder = '?' in sql or any(marker in sql for marker in (':', '@', '$'))
        if 'WITH RECURSIVE' in normalized and has_placeholder and _parameter_contains(parameters, target):
            matching.append((sql, parameters))

    assert matching, (
        f"No executed recursive CTE parameterized with target depth {target} was observed"
    )


def test_randomized_database_arbitrary_depths_and_required_query():
    """Exercise unseen data/depths and observe the recursive parameterized query being executed."""
    backup = '/tmp/company.db.verifier-backup'
    shutil.copy2(DB_PATH, backup)

    token = secrets.token_hex(5)
    max_depth = random.SystemRandom().randint(4, 7)
    rows = [(1, f'{token}_CEO', None)]
    expected = {0: [f'{token}_CEO']}
    managers = [1]
    next_id = 2

    for depth in range(1, max_depth + 1):
        current = []
        names = []
        for branch in range(2):
            name = f'{token}_d{depth}_{branch}_{secrets.token_hex(2)}'
            rows.append((next_id, name, managers[branch % len(managers)]))
            current.append(next_id)
            names.append(name)
            next_id += 1
        expected[depth] = sorted(names)
        managers = current

    # This disconnected row must not be treated as part of the CEO hierarchy.
    rows.append((next_id, f'{token}_disconnected', 999999))

    try:
        os.remove(DB_PATH)
        conn = sqlite3.connect(DB_PATH)
        conn.execute('CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER)')
        conn.executemany('INSERT INTO employees VALUES (?, ?, ?)', rows)
        conn.commit()
        conn.close()

        for target in (0, 1, max_depth, max_depth + 1):
            output_path = f'/home/user/output_depth_{target}.json'
            if os.path.exists(output_path):
                os.remove(output_path)

            _run_with_sql_trace(target)

            assert os.path.isfile(output_path), f"Output file missing for depth {target}"
            with open(output_path, 'r') as f:
                try:
                    data = json.load(f)
                except json.JSONDecodeError:
                    pytest.fail(f"Output for depth {target} is not valid JSON")

            assert data.get('target_depth') == target
            assert data.get('employees') == expected.get(target, [])
    finally:
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
        shutil.move(backup, DB_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
