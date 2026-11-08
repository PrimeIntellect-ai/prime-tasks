#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/get_subordinates.sh"
DB_PATH = "/home/user/db/org_chart.db"
LOG_PATH = "/home/user/top_vp.log"


def employee_rows():
    with sqlite3.connect(DB_PATH) as conn:
        return conn.execute(
            "SELECT emp_id, manager_id FROM employees ORDER BY emp_id"
        ).fetchall()


def expected_counts(rows):
    children = {}
    for emp_id, manager_id in rows:
        children.setdefault(manager_id, []).append(emp_id)

    def descendants(emp_id):
        total = 0
        stack = list(children.get(emp_id, []))
        seen = set()
        while stack:
            child = stack.pop()
            assert child not in seen, "employees contains a management cycle"
            seen.add(child)
            total += 1
            stack.extend(children.get(child, []))
        return total

    return {emp_id: descendants(emp_id) for emp_id, _ in rows}


def run_script(emp_id):
    return subprocess.run(
        [SCRIPT_PATH, str(emp_id)],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_output_vp1():
    result = run_script(2)
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    expected_output = "Subordinate count for 2: 7"
    assert expected_output in result.stdout.strip(), \
        f"Expected '{expected_output}', got '{result.stdout.strip()}'"


def test_script_output_director1():
    result = run_script(4)
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    expected_output = "Subordinate count for 4: 3"
    assert expected_output in result.stdout.strip(), \
        f"Expected '{expected_output}', got '{result.stdout.strip()}'"


def test_script_all_employees_exact_output():
    rows = employee_rows()
    counts = expected_counts(rows)
    for emp_id, _ in rows:
        result = run_script(emp_id)
        assert result.returncode == 0, \
            f"Script failed for employee {emp_id}: {result.stderr}"
        expected = f"Subordinate count for {emp_id}: {counts[emp_id]}"
        assert result.stdout.strip() == expected, \
            f"Expected exact output '{expected}', got '{result.stdout.strip()}'"


def test_hierarchy_metrics_table():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} does not exist."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute(
        "SELECT name FROM sqlite_master "
        "WHERE type='table' AND name='hierarchy_metrics';"
    )
    assert cursor.fetchone() is not None, "Table 'hierarchy_metrics' does not exist."

    # Retain the original specific assertions.
    cursor.execute("SELECT total_subordinates FROM hierarchy_metrics WHERE emp_id=1;")
    ceo_count = cursor.fetchone()
    assert ceo_count is not None and ceo_count[0] == 11, \
        "CEO (emp_id 1) should have 11 subordinates."

    cursor.execute("SELECT total_subordinates FROM hierarchy_metrics WHERE emp_id=2;")
    vp1_count = cursor.fetchone()
    assert vp1_count is not None and vp1_count[0] == 7, \
        "VP1 (emp_id 2) should have 7 subordinates."

    cursor.execute("SELECT total_subordinates FROM hierarchy_metrics WHERE emp_id=12;")
    ic6_count = cursor.fetchone()
    assert ic6_count is not None and ic6_count[0] == 0, \
        "IC6 (emp_id 12) should have 0 subordinates."

    schema = cursor.execute("PRAGMA table_info(hierarchy_metrics)").fetchall()
    assert len(schema) == 2, f"Unexpected hierarchy_metrics schema: {schema}"
    assert schema[0][1] == "emp_id" and schema[0][2].upper() == "INTEGER" \
        and schema[0][5] == 1, \
        f"emp_id must be INTEGER PRIMARY KEY; schema was {schema}"
    assert schema[1][1] == "total_subordinates" \
        and schema[1][2].upper() == "INTEGER", \
        f"total_subordinates must be INTEGER; schema was {schema}"

    rows = cursor.execute(
        "SELECT emp_id, manager_id FROM employees ORDER BY emp_id"
    ).fetchall()
    expected = expected_counts(rows)
    actual = dict(cursor.execute(
        "SELECT emp_id, total_subordinates FROM hierarchy_metrics"
    ).fetchall())
    assert actual == expected, \
        f"hierarchy_metrics does not contain the correct row for every employee: {actual}"
    conn.close()


def test_top_vp_log():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."
    with open(LOG_PATH, "r") as f:
        content = f.read().strip()
    assert content == "2:7", f"Expected log file content '2:7', got '{content}'"

    with sqlite3.connect(DB_PATH) as conn:
        candidates = conn.execute(
            "SELECT e.emp_id, h.total_subordinates "
            "FROM employees e JOIN hierarchy_metrics h ON h.emp_id=e.emp_id "
            "WHERE e.manager_id IS NOT NULL "
            "ORDER BY h.total_subordinates DESC, e.emp_id ASC"
        ).fetchall()
    assert candidates, "No non-CEO employees were found"
    expected = f"{candidates[0][0]}:{candidates[0][1]}"
    assert content == expected, f"Expected derived top VP '{expected}', got '{content}'"


def test_script_uses_parameterized_recursive_query():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    # Retain the original parameter-marker assertion.
    assert "?" in content or "@" in content or ":" in content or "$" in content, \
        "Script does not appear to use parameterized queries."

    assert re.search(r"\bWITH\s+RECURSIVE\b", content, re.IGNORECASE), \
        "Script does not contain a recursive CTE."

    binding = re.search(
        r"\.parameter\s+set\s+((?:[:@$][A-Za-z_][A-Za-z0-9_]*)|(?:\?[0-9]+))(?=\s)",
        content,
        re.IGNORECASE,
    )
    assert binding, \
        "Script must bind the employee ID with SQLite's .parameter set command."
    marker = binding.group(1)
    assert len(re.findall(re.escape(marker), content)) >= 2, \
        "The bound SQLite parameter is not used by the query."


def test_script_queries_live_database_for_unseen_hierarchy():
    # Add unpredictable employees after submission. A hardcoded script cannot know
    # these IDs or their resulting counts. Restore the submitted database afterward.
    fd, backup_path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)

    base = 1000000 + secrets.randbelow(100000000)
    new_ids = [base + i for i in range(6)]
    try:
        with sqlite3.connect(DB_PATH) as conn:
            conn.executemany(
                "INSERT INTO employees(emp_id, name, manager_id) VALUES (?, ?, ?)",
                [
                    (new_ids[0], "audit_root", 3),
                    (new_ids[1], "audit_child_a", new_ids[0]),
                    (new_ids[2], "audit_child_b", new_ids[0]),
                    (new_ids[3], "audit_grandchild", new_ids[1]),
                    (new_ids[4], "audit_deep_child", new_ids[3]),
                    (new_ids[5], "audit_leaf", new_ids[2]),
                ],
            )

        rows = employee_rows()
        counts = expected_counts(rows)
        for emp_id in [3] + new_ids:
            result = run_script(emp_id)
            assert result.returncode == 0, \
                f"Script failed for live employee {emp_id}: {result.stderr}"
            expected = f"Subordinate count for {emp_id}: {counts[emp_id]}"
            assert result.stdout.strip() == expected, \
                f"Live-database query expected '{expected}', got '{result.stdout.strip()}'"

        before = employee_rows()
        run_script("2); DROP TABLE employees;--")
        assert employee_rows() == before, \
            "Unsafe argument handling changed the employees table"
    finally:
        shutil.copy2(backup_path, DB_PATH)
        for suffix in ("-wal", "-shm", "-journal"):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        os.remove(backup_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
