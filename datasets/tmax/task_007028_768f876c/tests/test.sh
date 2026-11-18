#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import sqlite3
import subprocess
import uuid

RAW = "/home/user/raw_org.jsonl"
DB = "/home/user/org.db"
CSV = "/home/user/hierarchy_budgets.csv"
SQL = "/home/user/recursive.sql"
PLAN = "/home/user/plan.txt"
MANIFEST = "/home/user/etl_job/Cargo.toml"


def load_jsonl(path):
    rows = []
    with open(path, "r") as f:
        for line in f:
            if line.strip():
                rows.append(json.loads(line))
    return rows


def expected_budgets(rows):
    employees = {r["emp_id"]: r for r in rows}
    children = {emp_id: [] for emp_id in employees}
    for emp_id, row in employees.items():
        manager = row["manager_id"]
        if manager is not None and manager in children:
            children[manager].append(emp_id)

    def budget(emp_id, visiting=None):
        visiting = set() if visiting is None else visiting
        assert emp_id not in visiting, "Input hierarchy contains a cycle"
        visiting.add(emp_id)
        total = int(employees[emp_id]["salary"])
        for child in children[emp_id]:
            total += budget(child, visiting)
        visiting.remove(emp_id)
        return total

    result = [(emp_id, budget(emp_id)) for emp_id in employees]
    return sorted(result, key=lambda row: (-row[1], row[0]))


def run_job():
    for path in (DB, CSV, SQL, PLAN):
        if os.path.lexists(path):
            os.remove(path)
    result = subprocess.run(
        ["cargo", "run", "--manifest-path", MANIFEST],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=240,
    )
    assert result.returncode == 0, "cargo run failed:\n" + result.stdout[-8000:]


def assert_pipeline_outputs(input_rows):
    expected = expected_budgets(input_rows)

    assert os.path.isfile(DB), f"Database file {DB} does not exist."
    conn = sqlite3.connect(DB)
    try:
        cur = conn.cursor()
        cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='employees';")
        assert cur.fetchone() is not None, "Table 'employees' does not exist in the database."

        cur.execute("PRAGMA table_info(employees);")
        info = cur.fetchall()
        columns = {row[1]: row[2].upper() for row in info}
        assert "emp_id" in columns, "Column 'emp_id' missing."
        assert "name" in columns, "Column 'name' missing."
        assert "manager_id" in columns, "Column 'manager_id' missing."
        assert "salary" in columns, "Column 'salary' missing."
        assert columns["emp_id"] == "TEXT"
        assert columns["name"] == "TEXT"
        assert columns["manager_id"] == "TEXT"
        assert columns["salary"] == "INTEGER"
        assert next(row for row in info if row[1] == "emp_id")[5] == 1, "emp_id is not the primary key"

        cur.execute("SELECT emp_id, name, manager_id, salary FROM employees ORDER BY emp_id")
        actual_employees = cur.fetchall()
        expected_employees = sorted(
            [(r["emp_id"], r["name"], r["manager_id"], int(r["salary"])) for r in input_rows]
        )
        assert actual_employees == expected_employees, "The employees table does not exactly match the JSONL input"

        assert os.path.isfile(SQL), f"SQL file {SQL} does not exist."
        with open(SQL, "r") as f:
            query = f.read().strip()
        assert "WITH RECURSIVE" in query.upper(), "recursive.sql is missing WITH RECURSIVE"

        try:
            query_rows = cur.execute(query).fetchall()
        except sqlite3.Error as exc:
            raise AssertionError(f"recursive.sql is not executable against org.db: {exc}")
        assert all(len(row) == 2 for row in query_rows), "Recursive query must return exactly two columns"
        normalized_query_rows = [(str(row[0]), int(row[1])) for row in query_rows]
        assert normalized_query_rows == expected, "The saved recursive query does not produce the required sorted budgets"

        explain_rows = cur.execute("EXPLAIN QUERY PLAN " + query).fetchall()
    finally:
        conn.close()

    assert os.path.isfile(CSV), f"CSV file {CSV} does not exist."
    with open(CSV, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    expected_lines = [f"{emp_id},{budget}" for emp_id, budget in expected]
    assert actual_lines == expected_lines, "hierarchy_budgets.csv does not match the recursive result"

    assert os.path.isfile(PLAN), f"Plan file {PLAN} does not exist."
    with open(PLAN, "r") as f:
        plan_content = f.read().strip()
    assert plan_content, f"The file {PLAN} is empty."
    assert any(word in plan_content.upper() for word in ("SCAN", "SEARCH", "EXECUTE")), \
        f"The file {PLAN} does not look like valid SQLite EXPLAIN QUERY PLAN output."
    details = [str(row[3]).strip() for row in explain_rows if len(row) >= 4 and str(row[3]).strip()]
    assert details, "SQLite returned no EXPLAIN QUERY PLAN details"
    for detail in details:
        assert detail in plan_content, f"plan.txt is missing EXPLAIN QUERY PLAN detail: {detail}"


def test_project_runs_pipeline_on_unseen_input():
    assert os.path.isfile(MANIFEST), "The required Rust Cargo.toml does not exist"
    src_dir = "/home/user/etl_job/src"
    assert os.path.isdir(src_dir), "The Rust project's src directory does not exist"
    rust_sources = []
    for root, _, files in os.walk(src_dir):
        rust_sources.extend(os.path.join(root, name) for name in files if name.endswith(".rs"))
    assert rust_sources, "The Cargo project contains no Rust source files"
    assert any(os.path.getsize(path) > 0 for path in rust_sources), "The Rust source files are empty"

    with open(RAW, "r") as f:
        original_raw = f.read()

    token = uuid.uuid4().hex[:10]
    base = int(uuid.uuid4().hex[:6], 16) % 50000 + 51000
    probe = [
        {"emp_id": f"R-{token}", "name": "Probe Root", "manager_id": None, "salary": base + 9000},
        {"emp_id": f"A-{token}", "name": "Alpha, Lead", "manager_id": f"R-{token}", "salary": base + 3100},
        {"emp_id": f"B-{token}", "name": "Beta", "manager_id": f"R-{token}", "salary": base + 2700},
        {"emp_id": f"C-{token}", "name": "Gamma", "manager_id": f"A-{token}", "salary": base + 1300},
        {"emp_id": f"D-{token}", "name": "Delta", "manager_id": f"C-{token}", "salary": base + 700},
        {"emp_id": f"E-{token}", "name": "Epsilon", "manager_id": f"B-{token}", "salary": base + 1100},
        {"emp_id": f"F-{token}", "name": "Zeta", "manager_id": f"B-{token}", "salary": base + 900},
    ]

    try:
        with open(RAW, "w") as f:
            for row in probe:
                f.write(json.dumps(row) + "\n")
        run_job()
        assert_pipeline_outputs(probe)
    finally:
        with open(RAW, "w") as f:
            f.write(original_raw)

    # Leave and verify artifacts generated by the program from the instructed input.
    run_job()
    assert_pipeline_outputs(load_jsonl(RAW))


def test_sqlite_database_and_schema():
    assert os.path.exists(DB), f"Database file {DB} does not exist."
    conn = sqlite3.connect(DB)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='employees';")
    assert cursor.fetchone() is not None, "Table 'employees' does not exist in the database."
    cursor.execute("PRAGMA table_info(employees);")
    columns = {row[1]: row[2] for row in cursor.fetchall()}
    assert "emp_id" in columns
    assert "name" in columns
    assert "manager_id" in columns
    assert "salary" in columns
    cursor.execute("SELECT COUNT(*) FROM employees;")
    assert cursor.fetchone()[0] > 0, "The 'employees' table is empty."
    conn.close()


def test_hierarchy_budgets_csv():
    rows = load_jsonl(RAW)
    expected_lines = [f"{emp_id},{budget}" for emp_id, budget in expected_budgets(rows)]
    assert os.path.exists(CSV), f"CSV file {CSV} does not exist."
    with open(CSV, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert len(actual_lines) == len(expected_lines)
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Row {i+1} mismatch. Expected '{expected}', got '{actual}'."


def test_recursive_sql():
    assert os.path.exists(SQL), f"SQL file {SQL} does not exist."
    with open(SQL, "r") as f:
        content = f.read().upper()
    assert "WITH RECURSIVE" in content


def test_explain_plan():
    assert os.path.exists(PLAN), f"Plan file {PLAN} does not exist."
    with open(PLAN, "r") as f:
        content = f.read().strip()
    assert len(content) > 0, f"The file {PLAN} is empty."
    assert "SCAN" in content.upper() or "SEARCH" in content.upper() or "EXECUTE" in content.upper()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
