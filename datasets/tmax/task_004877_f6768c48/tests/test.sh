#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import csv

DB_PATH = "/home/user/corporate.db"
CSV_PATH = "/home/user/audit_report.csv"
CPP_PATH = "/home/user/process_audit.cpp"
BIN_PATH = "/home/user/process_audit"

def test_cpp_files_exist():
    assert os.path.isfile(CPP_PATH), f"C++ source file {CPP_PATH} is missing."
    assert os.path.isfile(BIN_PATH), f"Compiled binary {BIN_PATH} is missing."
    assert os.access(BIN_PATH, os.X_OK), f"Binary {BIN_PATH} is not executable."
    with open(BIN_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Binary {BIN_PATH} is not a compiled ELF executable."

def test_cpp_source_implements_required_sqlite_query():
    with open(CPP_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()

    # Ignore ordinary comments so merely describing the required features does not satisfy this check.
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source = re.sub(r"//[^\n]*", "", source)
    normalized = re.sub(r"[\s\"']+", "", source.lower())

    assert re.search(r"sqlite3_open(?:_v2)?\s*\(", source), "Source does not open the database through the SQLite C API."
    assert re.search(r"sqlite3_(?:exec|prepare(?:_v2|_v3)?|get_table)\s*\(", source), "Source does not execute SQL through the SQLite C API."
    assert "createindex" in normalized and "idx_emp_status" in normalized, "Source does not create idx_emp_status."
    assert "emp_id" in normalized and "status" in normalized, "Source does not define the required index columns."
    assert "withrecursive" in normalized, "Source query does not contain a recursive CTE."
    assert "over(" in normalized or "over(" in normalized.replace("window", ""), "Source query does not contain a window function."
    assert any(fn in normalized for fn in ("rank()", "dense_rank()", "row_number()")), "Source query does not calculate department rank with a window function."
    assert "partitionbydepartment" in normalized, "Window function is not partitioned by department."
    assert "denied" in normalized and "coalesce(" in normalized, "Source query does not calculate denied counts including zero-count employees."

def test_index_created():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_emp_status';")
    idx = cursor.fetchone()
    assert idx is not None, "Index 'idx_emp_status' was not created."

    # Check that the index covers emp_id and status
    cursor.execute("PRAGMA index_info('idx_emp_status');")
    columns = [row[2] for row in cursor.fetchall()]
    assert "emp_id" in columns and "status" in columns, "Index 'idx_emp_status' does not cover 'emp_id' and 'status'."

    conn.close()

def test_csv_report():
    assert os.path.isfile(CSV_PATH), f"CSV report {CSV_PATH} is missing."

    # Compute expected results dynamically
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    query = """
    WITH RECURSIVE org_chart AS (
        SELECT id as emp_id, name, department, 0 as depth
        FROM employees
        WHERE id = 1
        UNION ALL
        SELECT e.id, e.name, e.department, o.depth + 1
        FROM employees e
        JOIN org_chart o ON e.manager_id = o.emp_id
    ),
    denied_counts AS (
        SELECT emp_id, COUNT(*) as denied_count
        FROM access_logs
        WHERE status = 'DENIED'
        GROUP BY emp_id
    ),
    combined AS (
        SELECT o.emp_id, o.name, o.department, o.depth, COALESCE(d.denied_count, 0) as denied_count
        FROM org_chart o
        LEFT JOIN denied_counts d ON o.emp_id = d.emp_id
    )
    SELECT emp_id, name, department, depth, denied_count,
           RANK() OVER (PARTITION BY department ORDER BY denied_count DESC, emp_id ASC) as dept_rank
    FROM combined
    """

    cursor.execute(query)
    expected_rows = cursor.fetchall()
    conn.close()

    expected_dicts = []
    for row in expected_rows:
        expected_dicts.append({
            "emp_id": str(row[0]),
            "name": str(row[1]),
            "department": str(row[2]),
            "depth": str(row[3]),
            "denied_count": str(row[4]),
            "dept_rank": str(row[5])
        })

    # Read the actual CSV
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        actual_dicts = list(reader)

    # Check header
    expected_header = ["emp_id", "name", "department", "depth", "denied_count", "dept_rank"]
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        actual_header = f.readline().strip().split(",")
    assert actual_header == expected_header, f"CSV header is incorrect. Expected {expected_header}, got {actual_header}."

    # Sort both lists of dicts to compare
    def sort_key(d):
        return int(d["emp_id"])

    expected_dicts.sort(key=sort_key)
    actual_dicts.sort(key=sort_key)

    assert len(actual_dicts) == len(expected_dicts), f"Expected {len(expected_dicts)} rows in CSV, found {len(actual_dicts)}."

    for actual, expected in zip(actual_dicts, expected_dicts):
        assert actual == expected, f"Row mismatch. Expected {expected}, got {actual}."
TEST_EOF

mutate_database() {
    python3 - "$1" << 'PY_EOF'
import sqlite3
import sys

phase = int(sys.argv[1])
path = "/home/user/corporate.db"
conn = sqlite3.connect(path)
cur = conn.cursor()
cur.execute("DROP INDEX IF EXISTS idx_emp_status")
cur.execute("SELECT COALESCE(MAX(id), 0) FROM employees")
base = cur.fetchone()[0] + 1
department = f"VerifierDept{phase}"
rows = [
    (base, f"VerifierRoot{phase}", 1, department),
    (base + 1, f"VerifierChild{phase}", base, department),
    (base + 2, f"VerifierGrandchild{phase}", base + 1, department),
]
cur.executemany("INSERT INTO employees(id, name, manager_id, department) VALUES (?, ?, ?, ?)", rows)
logs = [
    (base, "dynamic-success", "SUCCESS", "2040-01-01"),
    (base + 1, "dynamic-a", "DENIED", "2040-01-02"),
    (base + 1, "dynamic-b", "DENIED", "2040-01-03"),
    (base + 2, "dynamic-a", "DENIED", "2040-01-04"),
    (base + 2, "dynamic-b", "DENIED", "2040-01-05"),
]
cur.executemany("INSERT INTO access_logs(emp_id, resource, status, timestamp) VALUES (?, ?, ?, ?)", logs)
conn.commit()
conn.close()
PY_EOF
}

verify_all() {
    test -f /home/user/process_audit.cpp || return 1
    test -f /home/user/process_audit || return 1
    test -x /home/user/process_audit || return 1

    # Invalidate both deliverables, alter the hierarchy and counts, then require the submitted
    # executable itself to recreate the index and report from the changed database.
    mutate_database 1 || return 1
    rm -f /home/user/audit_report.csv
    timeout 20s /home/user/process_audit || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    # Independently compile the submitted source and exercise that build on another unseen
    # database mutation, ensuring the working behavior is implemented by process_audit.cpp.
    g++ -std=c++17 /home/user/process_audit.cpp -lsqlite3 -o /tmp/process_audit_from_source || return 1
    mutate_database 2 || return 1
    rm -f /home/user/audit_report.csv
    timeout 20s /tmp/process_audit_from_source || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
}

if verify_all 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
