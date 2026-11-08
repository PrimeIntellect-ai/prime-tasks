#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import sqlite3
import subprocess
import tempfile

PROJECT_DIR = "/home/user/graph_etl"
MANIFEST = os.path.join(PROJECT_DIR, "Cargo.toml")
MAIN_RS = os.path.join(PROJECT_DIR, "src/main.rs")
DB_PATH = "/home/user/data.db"
OUTPUT_PATH = "/home/user/output_edges.csv"
INDEX_SQL_PATH = "/home/user/index.sql"


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def rust_bin_name():
    assert os.path.isfile(MANIFEST), f"Cargo manifest {MANIFEST} does not exist."
    assert os.path.isfile(MAIN_RS), f"Rust source {MAIN_RS} does not exist."

    result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", MANIFEST],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, f"Cargo metadata failed:\n{result.stderr}"
    metadata = json.loads(result.stdout)
    expected_source = os.path.realpath(MAIN_RS)
    bins = [
        target["name"]
        for package in metadata.get("packages", [])
        for target in package.get("targets", [])
        if "bin" in target.get("kind", [])
        and os.path.realpath(target.get("src_path", "")) == expected_source
    ]
    assert bins, f"{MAIN_RS} is not configured as a Cargo binary target."
    return bins[0]


def run_rust_project(bin_name):
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", MANIFEST, "--bin", bin_name],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, f"Rust project failed to run:\n{result.stderr}"
    assert os.path.isfile(OUTPUT_PATH), f"Running the Rust project did not create {OUTPUT_PATH}."


def test_output_edges_csv():
    file_path = "/home/user/output_edges.csv"
    assert os.path.exists(file_path), f"File {file_path} does not exist."

    lines = read_nonempty_lines(file_path)

    expected_edges = {
        "Alice,Alpha",
        "Bob,Alpha",
        "Bob,Beta",
        "Charlie,Beta"
    }

    assert set(lines) == expected_edges, f"Edges in {file_path} do not match the expected set. Found: {lines}"
    assert len(lines) == 4, f"{file_path} should contain exactly 4 edges, but found {len(lines)}."


def test_index_sql_file():
    file_path = "/home/user/index.sql"
    assert os.path.exists(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        original_content = f.read()
    content = original_content.lower()

    assert "create " in content and "index " in content, f"{file_path} does not contain a CREATE INDEX statement."
    assert "employee_projects" in content, f"{file_path} does not reference the employee_projects table."
    assert "emp_id" in content and "proj_id" in content, f"{file_path} does not reference both emp_id and proj_id columns."

    with tempfile.TemporaryDirectory() as temp_dir:
        temp_db = os.path.join(temp_dir, "index_validation.db")
        conn = sqlite3.connect(temp_db)
        try:
            conn.executescript("""
                CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT);
                CREATE TABLE projects (id INTEGER PRIMARY KEY, name TEXT);
                CREATE TABLE employee_projects (emp_id INTEGER, proj_id INTEGER);
            """)
            try:
                conn.executescript(original_content)
            except sqlite3.Error as exc:
                raise AssertionError(f"{file_path} is not valid executable SQLite SQL: {exc}")

            indexes = conn.execute("PRAGMA index_list('employee_projects')").fetchall()
            valid_index_found = False
            for idx in indexes:
                escaped_name = idx[1].replace("'", "''")
                columns = {row[2] for row in conn.execute(f"PRAGMA index_info('{escaped_name}')").fetchall()}
                if columns == {"emp_id", "proj_id"}:
                    valid_index_found = True
                    break
            assert valid_index_found, f"Executing {file_path} did not create a composite index covering emp_id and proj_id."
        finally:
            conn.close()


def test_index_applied_to_db():
    db_path = "/home/user/data.db"
    assert os.path.exists(db_path), f"Database {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("PRAGMA index_list('employee_projects');")
    indexes = cursor.fetchall()
    assert len(indexes) > 0, "No index found on the employee_projects table in the database."

    valid_index_found = False
    for idx in indexes:
        idx_name = idx[1]
        escaped_name = idx_name.replace("'", "''")
        cursor.execute(f"PRAGMA index_info('{escaped_name}');")
        columns = {row[2] for row in cursor.fetchall()}

        if columns == {"emp_id", "proj_id"}:
            valid_index_found = True
            break

    conn.close()

    assert valid_index_found, "No composite index covering both emp_id and proj_id was found on the employee_projects table."


def test_rust_project_executes_join_on_database_data():
    bin_name = rust_bin_name()
    token = secrets.token_hex(8)

    backup = sqlite3.connect(":memory:")
    source = sqlite3.connect(DB_PATH)
    try:
        source.backup(backup)
    finally:
        source.close()

    expected_lines = None
    try:
        conn = sqlite3.connect(DB_PATH)
        try:
            emp_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 1001 FROM employees").fetchone()[0]
            proj_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 2001 FROM projects").fetchone()[0]
            employee_name = f"VerifierEmployee_{token}"
            project_name = f"VerifierProject_{token}"
            conn.execute("INSERT INTO employees(id, name) VALUES (?, ?)", (emp_id, employee_name))
            conn.execute("INSERT INTO projects(id, name) VALUES (?, ?)", (proj_id, project_name))
            conn.execute("INSERT INTO employee_projects(emp_id, proj_id) VALUES (?, ?)", (emp_id, proj_id))
            conn.commit()

            expected_lines = {
                f"{employee},{project}"
                for employee, project in conn.execute("""
                    SELECT e.name, p.name
                    FROM employees AS e
                    JOIN employee_projects AS ep ON ep.emp_id = e.id
                    JOIN projects AS p ON p.id = ep.proj_id
                """).fetchall()
            }
            expected_count = conn.execute("SELECT COUNT(*) FROM employee_projects").fetchone()[0]
        finally:
            conn.close()

        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        run_rust_project(bin_name)
        actual_lines = read_nonempty_lines(OUTPUT_PATH)
        assert set(actual_lines) == expected_lines, \
            f"Rust extraction output does not match the database join. Found: {actual_lines}"
        assert len(actual_lines) == expected_count, \
            f"Rust extraction should emit exactly {expected_count} joined edges, found {len(actual_lines)}."
    finally:
        destination = sqlite3.connect(DB_PATH)
        try:
            backup.backup(destination)
        finally:
            destination.close()
            backup.close()

        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        run_rust_project(bin_name)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
