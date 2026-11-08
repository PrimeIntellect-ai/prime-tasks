#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import shutil
import sqlite3
import subprocess

SCRIPT_PATH = "/home/user/analyze_org.py"
DB_PATH = "/home/user/company.db"
JSON_PATH = "/home/user/evelyn_org.json"
TRACE_PATH = "/tmp/analyze_org_sql_trace.log"
HOOK_DIR = "/tmp/verifier_python_hook"

ORIGINAL_EXPECTED = {
    "name": "Evelyn",
    "salary": 100000,
    "reports": [
        {
            "name": "Bob",
            "salary": 80000,
            "reports": [
                {"name": "Dave", "salary": 50000, "reports": []},
                {"name": "Eve", "salary": 55000, "reports": []},
            ],
        },
        {
            "name": "Charlie",
            "salary": 60000,
            "reports": [
                {"name": "Alice", "salary": 45000, "reports": []}
            ],
        },
    ],
}


def install_sql_trace_hook():
    os.makedirs(HOOK_DIR, exist_ok=True)
    with open(os.path.join(HOOK_DIR, "sitecustomize.py"), "w") as f:
        f.write(r'''
import os
import sqlite3

_real_connect = sqlite3.connect

def _connect(*args, **kwargs):
    connection = _real_connect(*args, **kwargs)
    trace_path = os.environ.get("ANALYZE_ORG_TRACE")
    if trace_path:
        def record(statement):
            try:
                with open(trace_path, "a") as trace_file:
                    trace_file.write(statement.replace("\n", " ") + "\n")
            except Exception:
                pass
        connection.set_trace_callback(record)
    return connection

sqlite3.connect = _connect
''')


def expected_document(rows, salaries):
    by_id = {employee_id: (name, manager_id) for employee_id, name, manager_id in rows}
    roots = [employee_id for employee_id, (name, _) in by_id.items() if name == "Evelyn"]
    assert len(roots) == 1

    children = {}
    for employee_id, (_, manager_id) in by_id.items():
        children.setdefault(manager_id, []).append(employee_id)

    def build(employee_id):
        name = by_id[employee_id][0]
        report_ids = sorted(children.get(employee_id, []), key=lambda child: by_id[child][0])
        return {
            "name": name,
            "salary": salaries[employee_id],
            "reports": [build(child) for child in report_ids],
        }

    return build(roots[0])


def remove_database_files():
    for suffix in ("", "-wal", "-shm", "-journal"):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass


def create_database(rows, salaries):
    remove_database_files()
    connection = sqlite3.connect(DB_PATH)
    try:
        connection.executescript("""
            CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER);
            CREATE TABLE salaries (employee_id INTEGER, salary INTEGER);
        """)
        shuffled_rows = list(rows)
        random.SystemRandom().shuffle(shuffled_rows)
        connection.executemany(
            "INSERT INTO employees (id, name, manager_id) VALUES (?, ?, ?)",
            shuffled_rows,
        )
        connection.executemany(
            "INSERT INTO salaries (employee_id, salary) VALUES (?, ?)",
            list(salaries.items()),
        )
        connection.commit()
    finally:
        connection.close()


def make_case(parent_indexes):
    rng = secrets.SystemRandom()
    ids = rng.sample(range(1000, 900000), len(parent_indexes))
    names = ["Evelyn"] + [f"Employee_{i}_{secrets.token_hex(4)}" for i in range(1, len(parent_indexes))]
    rows = []
    for index, parent_index in enumerate(parent_indexes):
        manager_id = None if parent_index is None else ids[parent_index]
        rows.append((ids[index], names[index], manager_id))
    salaries = {employee_id: rng.randrange(31000, 180001) for employee_id in ids}
    return rows, salaries


def run_and_check(expected):
    try:
        os.remove(JSON_PATH)
    except FileNotFoundError:
        pass
    try:
        os.remove(TRACE_PATH)
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env["ANALYZE_ORG_TRACE"] = TRACE_PATH
    env["PYTHONPATH"] = HOOK_DIR + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        capture_output=True,
        text=True,
        env=env,
        timeout=20,
    )
    assert result.returncode == 0, f"Script execution failed with error: {result.stderr}"

    expected_total = sum_salaries(expected)
    output = result.stdout.strip()
    assert output == str(expected_total), (
        f"Expected stdout to contain only total salary {expected_total}, got: {result.stdout!r}"
    )

    assert os.path.isfile(JSON_PATH), f"JSON output missing at {JSON_PATH}"
    try:
        with open(JSON_PATH, "r") as f:
            actual_json = json.load(f)
    except json.JSONDecodeError:
        raise AssertionError(f"File {JSON_PATH} does not contain valid JSON.")
    assert actual_json == expected, (
        "The generated JSON structure does not match the expected organizational chart."
    )

    assert os.path.isfile(TRACE_PATH), "No SQLite statements were observed during execution"
    with open(TRACE_PATH, "r") as f:
        statements = f.readlines()
    assert any(
        re.search(r"\bWITH\s+RECURSIVE\b", statement, re.IGNORECASE)
        and re.search(r"\bemployees\b", statement, re.IGNORECASE)
        for statement in statements
    ), "The script did not execute a recursive CTE over the employees table"


def sum_salaries(node):
    return node["salary"] + sum(sum_salaries(report) for report in node["reports"])


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"


def test_original_and_generated_databases():
    install_sql_trace_hook()
    backup_path = "/tmp/company.db.verifier-backup"
    shutil.copy2(DB_PATH, backup_path)
    try:
        # Preserve the original verifier's exact organizational-chart assertion.
        run_and_check(ORIGINAL_EXPECTED)
        assert sum_salaries(ORIGINAL_EXPECTED) == 390000

        # Exercise fresh databases whose names, IDs, salaries, insertion order,
        # totals, and expected documents are derived at verification time.
        for parent_indexes in (
            [None, 0, 0, 1, 1, 3, None, 6],
            [None, 0, 1, 2, 0, 4, None, 6, 7],
        ):
            rows, salaries = make_case(parent_indexes)
            expected = expected_document(rows, salaries)
            create_database(rows, salaries)
            run_and_check(expected)
    finally:
        remove_database_files()
        shutil.copy2(backup_path, DB_PATH)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
