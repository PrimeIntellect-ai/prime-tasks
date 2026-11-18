#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import sqlite3
import uuid

SCRIPT_PATH = "/home/user/get_network.sh"
DB_PATH = "/home/user/company.db"


def run_script(employee_id, limit, offset):
    return subprocess.run(
        [SCRIPT_PATH, str(employee_id), str(limit), str(offset)],
        capture_output=True,
        text=True,
        timeout=15,
    )


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    st = os.stat(SCRIPT_PATH)
    assert st.st_mode & stat.S_IXUSR, f"Script at {SCRIPT_PATH} is not executable"

    with open(SCRIPT_PATH, "r", errors="replace") as f:
        source = f.read()
    code = "\n".join(line for line in source.splitlines()
                     if not line.lstrip().startswith("#"))
    assert re.search(r"\bsqlite3\b", code), "Script must use the sqlite3 command-line tool"
    assert re.search(r"\bWITH\s+RECURSIVE\b", code, re.IGNORECASE), \
        "Script must contain a recursive CTE"


def test_indexes_created():
    # Run the script once to ensure indexes are created
    subprocess.run([SCRIPT_PATH, "5", "2", "0"], capture_output=True)

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Check for indexes on manager table
    cursor.execute("PRAGMA index_list('manager');")
    indexes = cursor.fetchall()

    # We need to ensure there are indexes covering emp_id and manager_id
    # PRAGMA index_info(index_name) gives columns
    indexed_columns = set()
    for idx in indexes:
        idx_name = idx[1]
        cursor.execute(f"PRAGMA index_info('{idx_name}');")
        cols = cursor.fetchall()
        if cols:
            # Add the first column of the index
            indexed_columns.add(cols[0][2])

    conn.close()

    assert 'emp_id' in indexed_columns, "Index on manager(emp_id) was not created."
    assert 'manager_id' in indexed_columns, "Index on manager(manager_id) was not created."


def test_script_output_1():
    result = run_script(5, 2, 0)
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"

    expected_output = """Chain: Alice CEO (Executive) -> Charlie VP (Engineering) -> Eve Dir (Engineering)
Subordinates:
7 | Grace Mgr | Engineering
9 | Ivan IC | Engineering
"""
    assert result.stdout.strip() == expected_output.strip(), f"Output mismatch for '5 2 0'. Got:\n{result.stdout}"


def test_script_output_2():
    result = run_script(5, 2, 1)
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"

    expected_output = """Chain: Alice CEO (Executive) -> Charlie VP (Engineering) -> Eve Dir (Engineering)
Subordinates:
9 | Ivan IC | Engineering
10 | Judy IC | Engineering
"""
    assert result.stdout.strip() == expected_output.strip(), f"Output mismatch for '5 2 1'. Got:\n{result.stdout}"


def test_script_output_3():
    result = run_script(3, 10, 0)
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"

    expected_output = """Chain: Alice CEO (Executive) -> Charlie VP (Engineering)
Subordinates:
5 | Eve Dir | Engineering
7 | Grace Mgr | Engineering
9 | Ivan IC | Engineering
10 | Judy IC | Engineering
"""
    assert result.stdout.strip() == expected_output.strip(), f"Output mismatch for '3 10 0'. Got:\n{result.stdout}"


def expected_output(conn, employee_id, limit, offset):
    employees = {
        row[0]: (row[1], row[2])
        for row in conn.execute("SELECT id, name, department FROM employees")
    }
    parent = {
        row[0]: row[1]
        for row in conn.execute("SELECT emp_id, manager_id FROM manager")
        if row[1] is not None
    }
    children = {}
    for emp_id, manager_id in conn.execute(
            "SELECT emp_id, manager_id FROM manager WHERE manager_id IS NOT NULL"):
        children.setdefault(manager_id, []).append(emp_id)

    chain = []
    current = employee_id
    seen = set()
    while current is not None:
        assert current not in seen, "Test database unexpectedly contains a management cycle"
        seen.add(current)
        chain.append(current)
        current = parent.get(current)
    chain.reverse()

    descendants = []
    stack = list(children.get(employee_id, []))
    seen = set()
    while stack:
        current = stack.pop()
        if current in seen:
            continue
        seen.add(current)
        descendants.append(current)
        stack.extend(children.get(current, []))
    descendants.sort()
    descendants = descendants[offset:offset + limit]

    chain_text = " -> ".join(
        f"{employees[i][0]} ({employees[i][1]})" for i in chain
    )
    lines = [f"Chain: {chain_text}", "Subordinates:"]
    lines.extend(f"{i} | {employees[i][0]} | {employees[i][1]}" for i in descendants)
    return "\n".join(lines)


def test_dynamic_recursive_traversal_and_pagination():
    # Add an unpredictable hierarchy after the fixed checks. This prevents a
    # submission from passing by hardcoding only the originally tested outputs.
    conn = sqlite3.connect(DB_PATH)
    token = uuid.uuid4().hex[:10]
    base = conn.execute("SELECT MAX(id) FROM employees").fetchone()[0] + 100
    ids = [base + i * 7 for i in range(6)]
    employee_rows = [
        (ids[0], f"RndA_{token}", "DynamicA"),
        (ids[1], f"RndB_{token}", "DynamicB"),
        (ids[2], f"RndC_{token}", "DynamicC"),
        (ids[3], f"RndD_{token}", "DynamicD"),
        (ids[4], f"RndE_{token}", "DynamicE"),
        (ids[5], f"RndF_{token}", "DynamicF"),
    ]
    manager_rows = [
        (ids[0], 2),
        (ids[1], ids[0]),
        (ids[2], ids[1]),
        (ids[3], ids[1]),
        (ids[4], ids[2]),
        (ids[5], 4),
    ]

    try:
        conn.executemany(
            "INSERT INTO employees(id, name, department) VALUES (?, ?, ?)",
            employee_rows,
        )
        conn.executemany(
            "INSERT INTO manager(emp_id, manager_id) VALUES (?, ?)",
            manager_rows,
        )
        conn.commit()

        cases = [
            (ids[1], 2, 1),       # Branching descendants with pagination
            (ids[4], 5, 0),       # Newly generated deep management chain
            (2, 4, 2),            # Mixes original and generated descendants
            (1, 5, 6),            # Traversal and pagination from the CEO
        ]
        for employee_id, limit, offset in cases:
            expected = expected_output(conn, employee_id, limit, offset)
            result = run_script(employee_id, limit, offset)
            assert result.returncode == 0, (
                f"Script failed for dynamic case {employee_id} {limit} {offset}: "
                f"{result.stderr}"
            )
            assert result.stdout.strip() == expected.strip(), (
                f"Output mismatch for dynamic case {employee_id} {limit} {offset}.\n"
                f"Expected:\n{expected}\nGot:\n{result.stdout}"
            )
    finally:
        conn.executemany("DELETE FROM manager WHERE emp_id = ?", [(i,) for i in ids])
        conn.executemany("DELETE FROM employees WHERE id = ?", [(i,) for i in ids])
        conn.commit()
        conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
