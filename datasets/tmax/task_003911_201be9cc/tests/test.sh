#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT_PATH = "/home/user/etl_extract.py"
JSON_PATH = "/home/user/audit_chain.json"
DB_PATH = "/home/user/data.db"
TRACE_DIR = "/tmp/etl_trace_hook"
TRACE_PATH = "/tmp/etl_sql_trace.jsonl"


def install_trace_hook():
    os.makedirs(TRACE_DIR, exist_ok=True)
    Path(TRACE_DIR, "sitecustomize.py").write_text(r'''
import json
import os
import sqlite3

_real_connect = sqlite3.connect

def _connect(*args, **kwargs):
    conn = _real_connect(*args, **kwargs)
    trace_path = os.environ.get("ETL_SQL_TRACE")
    if trace_path:
        def record(statement):
            try:
                with open(trace_path, "a", encoding="utf-8") as f:
                    f.write(json.dumps(statement) + "\\n")
            except Exception:
                pass
        conn.set_trace_callback(record)
    return conn

sqlite3.connect = _connect
''', encoding="utf-8")


def run_submission():
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)

    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = TRACE_DIR + (os.pathsep + old_pythonpath if old_pythonpath else "")
    env["ETL_SQL_TRACE"] = TRACE_PATH

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"etl_extract.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    statements = []
    if os.path.exists(TRACE_PATH):
        with open(TRACE_PATH, "r", encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    statements.append(json.loads(line))
    return statements


def clean_sql(statement):
    statement = re.sub(r"/\*.*?\*/", " ", statement, flags=re.S)
    statement = re.sub(r"--[^\n]*", " ", statement)
    return statement.strip().lower()


def assert_sql_contract(statements):
    cleaned = [clean_sql(s) for s in statements]
    reindex_positions = [
        i for i, sql in enumerate(cleaned)
        if re.match(r"^reindex(?:\s|;|$)", sql)
    ]
    select_positions = [
        i for i, sql in enumerate(cleaned)
        if re.search(r"\bselect\b", sql)
    ]

    assert reindex_positions, "The executed script did not run REINDEX"
    assert select_positions, "The executed script did not run a SELECT query"
    assert min(reindex_positions) < min(select_positions), (
        "REINDEX must execute before every SELECT query"
    )

    qualifying_queries = [
        sql for sql in cleaned
        if re.search(r"\bwith\s+recursive\b", sql)
        and re.search(r"\bjoin\b.{0,120}\bdepartments\b", sql, flags=re.S)
    ]
    assert qualifying_queries, (
        "No executed query used a recursive CTE together with a departments join"
    )


@pytest.fixture(scope="module", autouse=True)
def execute_artifact():
    assert os.path.exists(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file"
    assert os.path.getsize(SCRIPT_PATH) > 0, f"{SCRIPT_PATH} is empty"
    install_trace_hook()
    statements = run_submission()
    assert_sql_contract(statements)


def test_audit_chain_json_exists():
    assert os.path.exists(JSON_PATH), f"Output file missing at {JSON_PATH}"
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} is not a file"


def test_audit_chain_json_content():
    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{JSON_PATH} does not contain valid JSON")

    expected_data = [
        {
            "level": 0,
            "employee_id": 845,
            "employee_name": "Eve Engineer",
            "department_name": "Engineering",
            "manager_id": 404
        },
        {
            "level": 1,
            "employee_id": 404,
            "employee_name": "Diana Manager",
            "department_name": "Engineering",
            "manager_id": 42
        },
        {
            "level": 2,
            "employee_id": 42,
            "employee_name": "Charlie Director",
            "department_name": "Engineering",
            "manager_id": 10
        },
        {
            "level": 3,
            "employee_id": 10,
            "employee_name": "Bob VP",
            "department_name": "Operations",
            "manager_id": 1
        },
        {
            "level": 4,
            "employee_id": 1,
            "employee_name": "Alice CEO",
            "department_name": "Executive",
            "manager_id": None
        }
    ]

    assert isinstance(data, list), "JSON output should be a list of objects"
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, got {len(data)}"

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a dictionary"
        for key, expected_val in expected.items():
            assert key in actual, f"Missing key '{key}' in item at index {i}"
            assert actual[key] == expected_val, f"Mismatch for key '{key}' at index {i}: expected {expected_val}, got {actual[key]}"


def test_output_is_derived_from_database():
    original_db = Path(DB_PATH).read_bytes()
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute("UPDATE employees SET name = name || ' verified'")
        conn.execute("UPDATE departments SET name = name || ' verified'")
        conn.execute("UPDATE employees SET manager_id = 999 WHERE id = 845")
        conn.commit()

        expected = []
        employee_id = 845
        level = 0
        while employee_id is not None:
            row = conn.execute(
                "SELECT e.id, e.name, d.name, e.manager_id "
                "FROM employees AS e JOIN departments AS d ON d.id = e.dept_id "
                "WHERE e.id = ?",
                (employee_id,),
            ).fetchone()
            assert row is not None, f"Verifier fixture has a broken chain at {employee_id}"
            expected.append({
                "level": level,
                "employee_id": row[0],
                "employee_name": row[1],
                "department_name": row[2],
                "manager_id": row[3],
            })
            employee_id = row[3]
            level += 1
        conn.close()

        statements = run_submission()
        assert_sql_contract(statements)
        assert os.path.isfile(JSON_PATH), "Script did not create audit_chain.json"
        with open(JSON_PATH, "r", encoding="utf-8") as f:
            actual = json.load(f)
        assert actual == expected, "Output was not derived from the current database contents"
    finally:
        try:
            conn.close()
        except Exception:
            pass
        Path(DB_PATH).write_bytes(original_db)
        # Leave the requested artifact populated from the original database.
        statements = run_submission()
        assert_sql_contract(statements)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
