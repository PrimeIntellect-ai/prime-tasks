#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import sqlite3
import subprocess
import tempfile

CPP_PATH = "/home/user/audit_processor.cpp"
BIN_PATH = "/home/user/audit_processor"
DB_PATH = "/home/user/corp_auth.db"
REQ_PATH = "/home/user/access_requests.txt"
RESULTS_PATH = "/home/user/audit_results.txt"


def run_processor():
    subprocess.run([BIN_PATH], check=True, timeout=15)


def read_results():
    assert os.path.exists(RESULTS_PATH), f"Expected output file {RESULTS_PATH} is missing."
    assert os.path.isfile(RESULTS_PATH), f"{RESULTS_PATH} is not a file."
    with open(RESULTS_PATH, "r") as f:
        return f.read().strip().splitlines()


def derive_expected(db_path, request_path):
    conn = sqlite3.connect(db_path)
    try:
        employees = dict(conn.execute("SELECT emp_id, dept_id FROM employees"))
        parents = dict(conn.execute("SELECT dept_id, parent_dept_id FROM departments"))
        policies = dict(conn.execute("SELECT resource_id, required_dept_id FROM resource_policies"))
    finally:
        conn.close()

    expected = []
    with open(request_path, "r") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            emp_text, resource_id = line.split(",", 1)
            emp_id = int(emp_text)
            current = employees.get(emp_id)
            required = policies.get(resource_id)
            approved = False
            seen = set()
            while current is not None and current not in seen:
                if current == required:
                    approved = True
                    break
                seen.add(current)
                current = parents.get(current)
            status = "APPROVED" if approved and required is not None else "DENIED"
            expected.append(f"{emp_text},{resource_id},{status}")
    return expected


def test_cpp_source_code_exists_compiles_and_executes():
    assert os.path.exists(CPP_PATH), f"C++ source file {CPP_PATH} is missing."
    assert os.path.isfile(CPP_PATH), f"{CPP_PATH} is not a file."

    with open(CPP_PATH, "r") as f:
        code = f.read()

    assert "sqlite3.h" in code, "The C++ source code does not seem to include the sqlite3 header."
    lowered = code.lower()
    assert "with recursive" in lowered, "The C++ source code does not use a Recursive CTE."
    assert "sqlite3_bind_" in lowered, "The C++ source code does not appear to bind query parameters."

    if os.path.exists(BIN_PATH):
        os.remove(BIN_PATH)
    subprocess.run(
        ["g++", "-std=c++17", "-o", BIN_PATH, CPP_PATH, "-lsqlite3"],
        check=True,
        timeout=30,
    )
    assert os.path.isfile(BIN_PATH), "Compilation did not create the required binary."
    assert os.access(BIN_PATH, os.X_OK), "The compiled audit processor is not executable."
    run_processor()


def test_audit_results_exists_and_correct():
    content = read_results()
    expected_content = [
        "101,RES-A,APPROVED",
        "102,RES-A,APPROVED",
        "103,RES-A,APPROVED",
        "104,RES-B,DENIED",
        "102,RES-B,APPROVED",
        "103,RES-B,APPROVED",
        "102,RES-C,DENIED",
        "103,RES-C,APPROVED",
        "104,RES-C,DENIED",
        "101,RES-D,DENIED",
    ]
    assert expected_content == derive_expected(DB_PATH, REQ_PATH)
    assert content == expected_content, f"Content of {RESULTS_PATH} does not match the expected audit results."


def test_database_unchanged():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT COUNT(*) FROM employees;")
    assert cursor.fetchone()[0] == 4, "The employees table was modified."

    cursor.execute("SELECT COUNT(*) FROM departments;")
    assert cursor.fetchone()[0] == 6, "The departments table was modified."

    cursor.execute("SELECT COUNT(*) FROM resource_policies;")
    assert cursor.fetchone()[0] == 4, "The resource_policies table was modified."
    conn.close()


def test_access_requests_unchanged():
    assert os.path.exists(REQ_PATH), f"Access requests file {REQ_PATH} is missing."
    with open(REQ_PATH, "r") as f:
        content = f.read().strip().splitlines()

    expected_content = [
        "101,RES-A",
        "102,RES-A",
        "103,RES-A",
        "104,RES-B",
        "102,RES-B",
        "103,RES-B",
        "102,RES-C",
        "103,RES-C",
        "104,RES-C",
        "101,RES-D",
    ]
    assert content == expected_content, f"Content of {REQ_PATH} was modified."


def test_processor_handles_independent_hierarchy_and_requests():
    with open(DB_PATH, "rb") as f:
        original_db = f.read()
    with open(REQ_PATH, "rb") as f:
        original_requests = f.read()

    temp_dir = tempfile.mkdtemp(prefix="audit-verifier-")
    temp_db = os.path.join(temp_dir, "dynamic.db")
    conn = sqlite3.connect(temp_db)
    conn.executescript("""
        CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, dept_id INTEGER);
        CREATE TABLE departments (dept_id INTEGER PRIMARY KEY, dept_name TEXT, parent_dept_id INTEGER);
        CREATE TABLE resource_policies (resource_id TEXT PRIMARY KEY, required_dept_id INTEGER);
        INSERT INTO departments VALUES (10, 'Root', NULL);
        INSERT INTO departments VALUES (20, 'Child', 10);
        INSERT INTO departments VALUES (30, 'Sibling', 10);
        INSERT INTO departments VALUES (40, 'Grandchild', 20);
        INSERT INTO departments VALUES (50, 'Leaf', 30);
        INSERT INTO employees VALUES (201, 'One', 40);
        INSERT INTO employees VALUES (202, 'Two', 10);
        INSERT INTO employees VALUES (203, 'Three', 20);
        INSERT INTO employees VALUES (204, 'Four', 50);
        INSERT INTO resource_policies VALUES ('RROOT', 10);
        INSERT INTO resource_policies VALUES ('RCHILD', 20);
        INSERT INTO resource_policies VALUES ('RSIB', 30);
    """)
    conn.commit()
    conn.close()

    dynamic_requests = (
        "201,RROOT\n"
        "202,RCHILD\n"
        "203,RCHILD\n"
        "204,RSIB\n"
        "201,RSIB\n"
        "999,RROOT\n"
        "201,UNKNOWN\n"
    )

    try:
        shutil.copyfile(temp_db, DB_PATH)
        with open(REQ_PATH, "w") as f:
            f.write(dynamic_requests)

        expected = derive_expected(DB_PATH, REQ_PATH)
        run_processor()
        assert read_results() == expected, "The processor failed on an independently generated hierarchy and request set."
    finally:
        with open(DB_PATH, "wb") as f:
            f.write(original_db)
        with open(REQ_PATH, "wb") as f:
            f.write(original_requests)
        for suffix in ("-journal", "-wal", "-shm"):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        shutil.rmtree(temp_dir, ignore_errors=True)

    run_processor()
    assert read_results() == derive_expected(DB_PATH, REQ_PATH)
    with open(DB_PATH, "rb") as f:
        assert f.read() == original_db, "The processor modified the database."
    with open(REQ_PATH, "rb") as f:
        assert f.read() == original_requests, "The processor modified the access request file."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
