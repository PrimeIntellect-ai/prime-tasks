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

DB_PATH = "/home/user/compliance.db"
PROJECT_PATH = "/home/user/access_auditor"
CARGO_TOML_PATH = os.path.join(PROJECT_PATH, "Cargo.toml")
MAIN_RS_PATH = os.path.join(PROJECT_PATH, "src", "main.rs")
RESULT_TXT_PATH = "/home/user/audit_result.txt"
OPTIMIZE_SQL_PATH = "/home/user/optimize.sql"


def test_cargo_project_exists_and_uses_rusqlite():
    """Verify that the requested Rust Cargo project and rusqlite program exist."""
    assert os.path.isfile(CARGO_TOML_PATH), \
        f"Cargo project not found. Expected Cargo.toml at {CARGO_TOML_PATH}"
    assert os.path.isfile(MAIN_RS_PATH), \
        f"Rust source not found. Expected main.rs at {MAIN_RS_PATH}"

    with open(CARGO_TOML_PATH, "r", encoding="utf-8") as f:
        cargo_toml = f.read()
    assert re.search(r'(?m)^\s*name\s*=\s*["\']access_auditor["\']\s*$', cargo_toml), \
        "The Cargo package must be named access_auditor."
    assert re.search(r'(?mi)^\s*rusqlite\s*=', cargo_toml), \
        "Cargo.toml must declare rusqlite as a dependency."

    with open(MAIN_RS_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    assert re.search(r'\brusqlite\b', source), \
        "src/main.rs must use rusqlite."
    assert re.search(
        r'department\s*=\s*(?:\?\d*|[:@$][A-Za-z_][A-Za-z0-9_]*)',
        source,
        re.IGNORECASE,
    ), "The Finance department query must use a SQL parameter placeholder."
    assert re.search(
        r'params\s*!|named_params\s*!|params_from_iter|raw_bind_parameter|\.query(?:_map|_row)?\s*\(',
        source,
        re.IGNORECASE,
    ), "The SQL parameter must be bound through rusqlite's parameter APIs."


def test_audit_result():
    """Verify the existing result against the supplied database and its strict format."""
    assert os.path.exists(RESULT_TXT_PATH), \
        f"Audit result file not found at {RESULT_TXT_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    query = """
        SELECT e.name, COUNT(r.id) as cnt
        FROM employees e
        JOIN access_grants ag ON e.id = ag.emp_id
        JOIN resources r ON ag.resource_id = r.id
        WHERE e.department = 'Finance' AND r.sensitivity = 'HIGH'
        GROUP BY e.id
        ORDER BY cnt DESC, e.id ASC
        LIMIT 1;
    """
    cursor.execute(query)
    row = cursor.fetchone()
    conn.close()

    assert row is not None, "Could not compute expected result from the database."
    expected_output = f"{row[0]}:{row[1]}"

    with open(RESULT_TXT_PATH, "r", encoding="utf-8") as f:
        raw_content = f.read()
    actual_content = raw_content.strip()

    # Preserve the original result assertion and additionally enforce exact output.
    assert expected_output in actual_content, \
        f"Expected '{expected_output}' in {RESULT_TXT_PATH}, but found '{actual_content}'"
    assert actual_content == expected_output, \
        f"Expected exactly '{expected_output}', but found '{actual_content}'"
    assert re.fullmatch(re.escape(expected_output) + r"\n?", raw_content), \
        "audit_result.txt must contain only NAME:COUNT, optionally followed by one newline."


def _index_columns(conn, table):
    found = []
    for row in conn.execute(f'PRAGMA index_list("{table}")'):
        name = row[1]
        partial = bool(row[4]) if len(row) > 4 else False
        quoted_name = name.replace('"', '""')
        columns = [r[2] for r in conn.execute(f'PRAGMA index_info("{quoted_name}")')]
        found.append((columns, partial))
    return found


def test_optimize_sql_indexes():
    """Verify that optimize.sql contains valid indexes for every requested operation."""
    assert os.path.exists(OPTIMIZE_SQL_PATH), \
        f"SQL optimization file not found at {OPTIMIZE_SQL_PATH}"

    with open(OPTIMIZE_SQL_PATH, "r", encoding="utf-8") as f:
        original_content = f.read()
    content = original_content.lower()

    # Preserve the original textual assertions.
    assert re.search(r"create\s+(?:unique\s+)?index\s+.*?\s+on\s+employees\s*\(\s*.*?department.*?\s*\)", content), \
        "Missing CREATE INDEX statement for employees table on the department column."
    assert re.search(r"create\s+(?:unique\s+)?index\s+.*?\s+on\s+resources\s*\(\s*.*?sensitivity.*?\s*\)", content), \
        "Missing CREATE INDEX statement for resources table on the sensitivity column."

    has_emp_id = re.search(r"create\s+(?:unique\s+)?index\s+.*?\s+on\s+access_grants\s*\(\s*.*?emp_id.*?\s*\)", content)
    has_res_id = re.search(r"create\s+(?:unique\s+)?index\s+.*?\s+on\s+access_grants\s*\(\s*.*?resource_id.*?\s*\)", content)
    assert has_emp_id or has_res_id, \
        "Missing CREATE INDEX statement for access_grants table on emp_id and/or resource_id columns."
    assert has_emp_id and has_res_id, \
        "Indexes must cover both access_grants.emp_id and access_grants.resource_id."

    # Execute the submitted SQL and inspect the real index definitions rather than
    # trusting regex matches or comments.
    conn = sqlite3.connect(":memory:")
    conn.executescript("""
        CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department TEXT);
        CREATE TABLE resources (id INTEGER PRIMARY KEY, name TEXT, sensitivity TEXT);
        CREATE TABLE access_grants (emp_id INTEGER, resource_id INTEGER, grant_date TEXT);
    """)
    try:
        conn.executescript(original_content)
    except sqlite3.Error as exc:
        raise AssertionError(f"optimize.sql is not executable SQLite SQL: {exc}")

    employee_indexes = _index_columns(conn, "employees")
    resource_indexes = _index_columns(conn, "resources")
    grant_indexes = _index_columns(conn, "access_grants")
    conn.close()

    assert any(cols and cols[0].lower() == "department" and not partial
               for cols, partial in employee_indexes), \
        "employees must have a non-partial index led by department."
    assert any(cols and cols[0].lower() == "sensitivity" and not partial
               for cols, partial in resource_indexes), \
        "resources must have a non-partial index led by sensitivity."
    assert any(cols and cols[0].lower() == "emp_id" and not partial
               for cols, partial in grant_indexes), \
        "access_grants must have a non-partial index led by emp_id."
    assert any(cols and cols[0].lower() == "resource_id" and not partial
               for cols, partial in grant_indexes), \
        "access_grants must have a non-partial index led by resource_id."


def _install_test_database(finance_a, finance_b, winner):
    conn = sqlite3.connect(DB_PATH)
    conn.executescript("""
        CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department TEXT);
        CREATE TABLE resources (id INTEGER PRIMARY KEY, name TEXT, sensitivity TEXT);
        CREATE TABLE access_grants (emp_id INTEGER, resource_id INTEGER, grant_date TEXT);
    """)
    engineering = "Eng_" + secrets.token_hex(8)
    conn.executemany("INSERT INTO employees VALUES (?, ?, ?)", [
        (11, finance_a, "Finance"),
        (22, finance_b, "Finance"),
        (33, engineering, "Engineering"),
    ])
    conn.executemany("INSERT INTO resources VALUES (?, ?, ?)", [
        (101, "H1", "HIGH"), (102, "H2", "HIGH"),
        (103, "H3", "HIGH"), (104, "H4", "HIGH"),
        (105, "H5", "HIGH"), (106, "L1", "LOW"),
    ])

    if winner == finance_a:
        a_high, b_high = [101, 102, 103, 104], [101, 102]
        expected_count = 4
    else:
        a_high, b_high = [101], [101, 102, 103]
        expected_count = 3

    grants = [(11, rid, "2025-01-01") for rid in a_high]
    grants += [(22, rid, "2025-01-01") for rid in b_high]
    grants += [(11, 106, "2025-01-01"), (22, 106, "2025-01-01")]
    # Engineering has more HIGH grants and must not be selected.
    grants += [(33, rid, "2025-01-01") for rid in [101, 102, 103, 104, 105]]
    conn.executemany("INSERT INTO access_grants VALUES (?, ?, ?)", grants)
    conn.commit()
    conn.close()
    return f"{winner}:{expected_count}"


def test_compile_and_run_rust_program_on_derived_inputs(tmp_path):
    """Compile and execute the submitted program against unseen database contents."""
    db_backup = tmp_path / "compliance.db.backup"
    shutil.copy2(DB_PATH, db_backup)
    old_result = None
    if os.path.exists(RESULT_TXT_PATH):
        with open(RESULT_TXT_PATH, "rb") as f:
            old_result = f.read()

    try:
        for winner_is_a in (False, True):
            for suffix in ("-wal", "-shm", "-journal"):
                try:
                    os.remove(DB_PATH + suffix)
                except FileNotFoundError:
                    pass
            os.remove(DB_PATH)

            finance_a = "FinA_" + secrets.token_hex(10)
            finance_b = "FinB_" + secrets.token_hex(10)
            winner = finance_a if winner_is_a else finance_b
            expected = _install_test_database(finance_a, finance_b, winner)

            try:
                os.remove(RESULT_TXT_PATH)
            except FileNotFoundError:
                pass

            proc = subprocess.run(
                ["cargo", "run", "--quiet", "--manifest-path", CARGO_TOML_PATH],
                cwd=PROJECT_PATH,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=180,
            )
            assert proc.returncode == 0, \
                f"cargo run failed:\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
            assert os.path.isfile(RESULT_TXT_PATH), \
                "Running the Rust program did not create audit_result.txt."

            with open(RESULT_TXT_PATH, "r", encoding="utf-8") as f:
                raw = f.read()
            assert re.fullmatch(re.escape(expected) + r"\n?", raw), \
                f"For the verification database, expected exactly '{expected}', found '{raw}'."
    finally:
        for suffix in ("", "-wal", "-shm", "-journal"):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        shutil.copy2(db_backup, DB_PATH)
        if old_result is None:
            try:
                os.remove(RESULT_TXT_PATH)
            except FileNotFoundError:
                pass
        else:
            with open(RESULT_TXT_PATH, "wb") as f:
                f.write(old_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
