#!/bin/bash
set -u
mkdir -p /logs/verifier

run_checks() {
    python3 <<'PY'
import os
import re
import stat

path = "/home/user/query.c"
assert os.path.exists(path), f"{path} does not exist"
assert stat.S_ISREG(os.stat(path).st_mode), f"{path} is not a regular file"
with open(path, "r", encoding="utf-8", errors="replace") as f:
    source = f.read()
assert source.strip(), f"{path} is empty"

# Ignore comments when checking that the submitted source contains the required SQL.
clean = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
clean = re.sub(r"//[^\n]*", " ", clean)
assert re.search(r"\bWITH(?:\s|[\"']|\\[nrt])+\bRECURSIVE\b", clean, flags=re.I), \
    "query.c does not contain a WITH RECURSIVE query"
PY

    gcc /home/user/query.c -lsqlite3 -o /home/user/query || return 1
    test -f /home/user/query && test -x /home/user/query || return 1

    # Confirm the compiled program actually references SQLite connection and query APIs.
    nm -u /home/user/query 2>/dev/null | grep -Eq 'sqlite3_(open|open_v2|open16)' || return 1
    nm -u /home/user/query 2>/dev/null | grep -Eq 'sqlite3_(exec|prepare|prepare_v2|prepare_v3)' || return 1

    rm -f /home/user/results.csv
    timeout 15 /home/user/query || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

CSV_PATH = "/home/user/results.csv"

EXPECTED_OUTPUT = """4,Dave,Executive,2,120000.00
5,Eve,Engineering,2,110000.00
10,Judy,Sales,2,95000.00
7,Grace,Executive,3,90000.00"""

def test_results_csv_exists():
    """Verify that the results.csv file was generated."""
    assert os.path.isfile(CSV_PATH), f"File {CSV_PATH} was not found. Ensure the C program was compiled and executed."

def test_results_csv_content():
    """Verify the contents of the results.csv file match the expected query output."""
    assert os.path.isfile(CSV_PATH), f"File {CSV_PATH} is missing."

    with open(CSV_PATH, "r") as f:
        content = f.read().strip()

    expected_lines = EXPECTED_OUTPUT.strip().split("\n")
    actual_lines = content.split("\n")

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} rows, but got {len(actual_lines)} rows."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual.strip() == expected.strip(), f"Row {i+1} mismatch.\nExpected: {expected}\nGot:      {actual}"
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    local backup="/tmp/company.db.verifier.$$"
    cp /home/user/company.db "$backup" || return 1

    python3 <<'PY'
import secrets
import sqlite3

path = "/home/user/company.db"
conn = sqlite3.connect(path)
try:
    token = secrets.token_hex(4)
    for dep_id, prefix in [(1, "Executive"), (2, "Engineering"), (3, "Sales")]:
        conn.execute("UPDATE departments SET name=? WHERE id=?", (f"{prefix}_{token}", dep_id))

    rows = conn.execute("SELECT id FROM employees ORDER BY id").fetchall()
    for index, (employee_id,) in enumerate(rows):
        salary = 60000 + secrets.randbelow(180000) + index / 100.0
        conn.execute("UPDATE employees SET salary=? WHERE id=?", (salary, employee_id))

    next_id = 1000 + secrets.randbelow(100000)
    conn.execute(
        "INSERT INTO employees(id,name,department_id,manager_id,salary) VALUES(?,?,?,?,?)",
        (next_id, f"Worker_{token}", 2, 3, 70000 + secrets.randbelow(160000) + 0.37),
    )
    conn.execute(
        "INSERT INTO employees(id,name,department_id,manager_id,salary) VALUES(?,?,?,?,?)",
        (next_id + 1, f"Intern_{token}", 3, next_id, 50000 + secrets.randbelow(100000) + 0.61),
    )
    conn.commit()

    result = conn.execute("""
        WITH RECURSIVE hierarchy(id, name, department_id, manager_id, salary, level) AS (
            SELECT id, name, department_id, manager_id, salary, 0
            FROM employees
            WHERE manager_id IS NULL
            UNION ALL
            SELECT e.id, e.name, e.department_id, e.manager_id, e.salary, h.level + 1
            FROM employees AS e
            JOIN hierarchy AS h ON e.manager_id = h.id
        )
        SELECT h.id, h.name, d.name, h.level, h.salary
        FROM hierarchy AS h
        JOIN departments AS d ON d.id = h.department_id
        ORDER BY h.level ASC, h.salary DESC
        LIMIT 4 OFFSET 3
    """).fetchall()

    assert len(result) == 4
    with open("/tmp/expected_dynamic.csv", "w", encoding="utf-8") as f:
        f.write("\n".join(
            f"{employee_id},{name},{department},{level},{salary:.2f}"
            for employee_id, name, department, level, salary in result
        ))
finally:
    conn.close()
PY
    if [ $? -ne 0 ]; then
        cp "$backup" /home/user/company.db
        rm -f "$backup"
        return 1
    fi

    rm -f /home/user/results.csv
    local dynamic_status=0
    timeout 15 /home/user/query || dynamic_status=1

    if [ "$dynamic_status" -eq 0 ]; then
        python3 <<'PY' || dynamic_status=1
import os

actual_path = "/home/user/results.csv"
expected_path = "/tmp/expected_dynamic.csv"
assert os.path.isfile(actual_path), "The program did not generate results.csv on the modified database"
with open(actual_path, "r", encoding="utf-8") as f:
    actual = f.read().strip().split("\n")
with open(expected_path, "r", encoding="utf-8") as f:
    expected = f.read().strip().split("\n")
assert len(actual) == len(expected), f"Expected {len(expected)} rows, got {len(actual)}"
for i, (got, wanted) in enumerate(zip(actual, expected), 1):
    assert got.strip() == wanted.strip(), f"Dynamic row {i} mismatch: expected {wanted!r}, got {got!r}"
PY
    fi

    cp "$backup" /home/user/company.db || dynamic_status=1
    rm -f "$backup"

    # Leave results.csv corresponding to the restored database.
    if [ "$dynamic_status" -eq 0 ]; then
        rm -f /home/user/results.csv
        timeout 15 /home/user/query || dynamic_status=1
    fi

    [ "$dynamic_status" -eq 0 ] || return 1
    return 0
}

if run_checks 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
