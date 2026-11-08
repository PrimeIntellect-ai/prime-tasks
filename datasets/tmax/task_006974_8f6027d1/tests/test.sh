#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import sqlite3
import subprocess

DB_PATH = "/home/user/hr_data.db"
CYPHER_PATH = "/home/user/import.cypher"
BINARY_PATH = "/home/user/convert"
SOURCE_PATH = "/home/user/convert.cpp"


def expected_content_from_db():
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    query = """
    SELECT emp_id, manager_id, salary, dept
    FROM (
        SELECT emp_id, manager_id, salary, dept,
               ROW_NUMBER() OVER(PARTITION BY emp_id ORDER BY event_timestamp DESC) as rn
        FROM emp_events
    ) tmp
    WHERE rn = 1
    ORDER BY emp_id ASC
    """
    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()

    expected_blocks = []
    for emp_id, manager_id, salary, dept in rows:
        if manager_id == -1:
            continue
        salary_str = str(int(salary)) if salary == int(salary) else str(salary)
        expected_blocks.append(
            f"MERGE (e:Employee {{id: {emp_id}}}) SET e.salary = {salary_str}, e.dept = '{dept}';\n"
            f"MERGE (m:Employee {{id: {manager_id}}});\n"
            f"MERGE (e)-[:REPORTS_TO]->(m);"
        )
    return expected_blocks


def assert_cypher_matches_database():
    assert os.path.exists(CYPHER_PATH), f"{CYPHER_PATH} does not exist."
    assert os.path.isfile(CYPHER_PATH), f"{CYPHER_PATH} is not a file."
    with open(CYPHER_PATH, "r") as f:
        actual_content = f.read().strip()

    expected_blocks = expected_content_from_db()
    actual_blocks = [block.strip() for block in actual_content.split('\n\n') if block.strip()]
    assert len(actual_blocks) == len(expected_blocks), (
        f"Expected {len(expected_blocks)} employee blocks in the Cypher script, "
        f"but found {len(actual_blocks)}."
    )
    for i, (actual_block, expected_block) in enumerate(zip(actual_blocks, expected_blocks)):
        actual_lines = [line.strip() for line in actual_block.split('\n') if line.strip()]
        expected_lines = [line.strip() for line in expected_block.split('\n') if line.strip()]
        assert actual_lines == expected_lines, (
            f"Employee block {i+1} does not match expected output.\n"
            f"Expected:\n{expected_block}\n\nActual:\n{actual_block}"
        )


def strip_cpp_comments(text):
    out = []
    i = 0
    state = "code"
    while i < len(text):
        c = text[i]
        n = text[i + 1] if i + 1 < len(text) else ""
        if state == "code":
            if c == '/' and n == '/':
                state = "line"
                out.extend("  ")
                i += 2
                continue
            if c == '/' and n == '*':
                state = "block"
                out.extend("  ")
                i += 2
                continue
            if c == '"':
                state = "string"
            elif c == "'":
                state = "char"
            out.append(c)
        elif state == "line":
            if c == '\n':
                state = "code"
                out.append(c)
            else:
                out.append(' ')
        elif state == "block":
            if c == '*' and n == '/':
                out.extend("  ")
                i += 2
                state = "code"
                continue
            out.append('\n' if c == '\n' else ' ')
        else:
            out.append(c)
            if c == '\\' and i + 1 < len(text):
                out.append(text[i + 1])
                i += 2
                continue
            if (state == "string" and c == '"') or (state == "char" and c == "'"):
                state = "code"
        i += 1
    return ''.join(out)


def install_dynamic_database():
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass

    base = secrets.randbelow(5000000) + 1000000
    token = secrets.token_hex(5)
    rows = [
        (base + 3, 41, 41000, "Old_" + token, "2025-01-01 10:00:00"),
        (base + 1, 51, 51000, "Current_" + token, "2026-06-01 10:00:00"),
        (base + 1, 40, 40000, "Stale_" + token, "2024-01-01 10:00:00"),
        (base + 2, -1, 0, "TerminatedOld_" + token, "2024-03-01 10:00:00"),
        (base + 4, 77, 73000, "Solo_" + token, "2026-01-15 12:00:00"),
        (base + 2, 61, 62000, "Reactivated_" + token, "2026-08-01 10:00:00"),
        (base + 3, -1, 0, "Terminated_" + token, "2026-09-01 10:00:00"),
    ]
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""CREATE TABLE emp_events (
        event_id INTEGER PRIMARY KEY,
        emp_id INTEGER,
        manager_id INTEGER,
        salary REAL,
        dept TEXT,
        event_timestamp DATETIME
    )""")
    conn.executemany(
        "INSERT INTO emp_events (emp_id, manager_id, salary, dept, event_timestamp) VALUES (?, ?, ?, ?, ?)",
        rows,
    )
    conn.commit()
    conn.close()


def run_and_check(program):
    install_dynamic_database()
    with open(CYPHER_PATH, "w") as f:
        f.write("SENTINEL: converter did not regenerate this file\n")
    result = subprocess.run(
        [program], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"{program} exited with {result.returncode}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert_cypher_matches_database()


def test_convert_binary_exists():
    """Check if the compiled C++ binary exists and is executable."""
    assert os.path.exists(BINARY_PATH), f"{BINARY_PATH} does not exist."
    assert os.path.isfile(BINARY_PATH), f"{BINARY_PATH} is not a file."
    assert os.access(BINARY_PATH, os.X_OK), f"{BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY_PATH} is not a compiled ELF binary."


def test_import_cypher_exists_and_correct():
    """Check the originally generated Cypher script against the supplied database."""
    assert_cypher_matches_database()


def test_source_exists_uses_sqlite_and_window_function():
    assert os.path.exists(SOURCE_PATH), f"{SOURCE_PATH} does not exist."
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a file."
    with open(SOURCE_PATH, "r", encoding="utf-8") as f:
        source = strip_cpp_comments(f.read())
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", source), "convert.cpp must include sqlite3.h."
    assert re.search(r"\bsqlite3_open(?:_v2)?\s*\(", source), "convert.cpp must open SQLite through the SQLite3 API."
    assert re.search(r"\bsqlite3_(?:prepare(?:_v2|_v3)?|exec)\s*\(", source), "convert.cpp must execute SQL through the SQLite3 API."
    assert re.search(r"\bOVER\b", source, re.IGNORECASE), "The SQL query must use an OVER clause."
    assert re.search(r"\b(?:ROW_NUMBER|RANK|DENSE_RANK|FIRST_VALUE|LAST_VALUE|NTH_VALUE|LAG|LEAD)\s*\(", source, re.IGNORECASE), "The SQL query must use a window function."


def test_converter_programs_generate_output_from_database():
    rebuilt = "/tmp/submitted_convert"
    result = subprocess.run(
        ["g++", "-std=c++17", SOURCE_PATH, "-lsqlite3", "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"convert.cpp failed to compile.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    run_and_check(BINARY_PATH)
    run_and_check(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
