#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import shutil
import sqlite3
import subprocess
import tempfile
import pytest

DB_PATH = "/home/user/graph.db"
SOURCE_PATH = "/home/user/triangle_analyzer.c"
QUERY_PLAN_PATH = "/home/user/query_plan.txt"
MAX_TRIANGLE_PATH = "/home/user/max_triangle.txt"
EXECUTABLE_PATH = "/home/user/triangle_analyzer"

QUERY = '''
    SELECT e1.src, COUNT(*) as triangles
    FROM edges e1
    JOIN edges e2 ON e1.dst = e2.src
    JOIN edges e3 ON e2.dst = e3.src
    WHERE e3.dst = e1.src
    GROUP BY e1.src
    ORDER BY triangles DESC
    LIMIT 1;
'''

def expected_result():
    conn = sqlite3.connect(DB_PATH)
    try:
        result = conn.execute(QUERY).fetchone()
    finally:
        conn.close()
    assert result is not None, "Database has no triangles."
    return f"{result[0]},{result[1]}"

def expected_plan():
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("EXPLAIN QUERY PLAN " + QUERY).fetchall()
    finally:
        conn.close()
    return [str(row[3]) for row in rows]

def read_result():
    assert os.path.exists(MAX_TRIANGLE_PATH), f"Max triangle output {MAX_TRIANGLE_PATH} is missing."
    with open(MAX_TRIANGLE_PATH, "r") as f:
        return f.read().strip()

def read_plan():
    assert os.path.exists(QUERY_PLAN_PATH), f"Query plan output {QUERY_PLAN_PATH} is missing."
    with open(QUERY_PLAN_PATH, "r") as f:
        return f.read().splitlines()

def run_clean(executable):
    for path in (QUERY_PLAN_PATH, MAX_TRIANGLE_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    subprocess.run([executable], check=True, timeout=30)
    assert os.path.isfile(QUERY_PLAN_PATH), "The executable did not generate query_plan.txt."
    assert os.path.isfile(MAX_TRIANGLE_PATH), "The executable did not generate max_triangle.txt."

def assert_generated_outputs():
    assert read_result() == expected_result(), "The executable generated an incorrect analytics result."
    assert read_plan() == expected_plan(), "query_plan.txt is not the literal detail column from EXPLAIN QUERY PLAN."

def test_idx_stale_removed():
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} missing."
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_stale';")
    result = c.fetchone()
    conn.close()
    assert result is None, "The stale index 'idx_stale' was not removed."

def test_new_index_created():
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} missing."
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='edges';")
    indexes = c.fetchall()
    conn.close()
    assert len(indexes) > 0, "No indexes found on the 'edges' table. An optimal index should have been created."

    conn = sqlite3.connect(DB_PATH)
    try:
        optimal = False
        for (name,) in indexes:
            escaped = name.replace("'", "''")
            columns = [row[2] for row in conn.execute(f"PRAGMA index_info('{escaped}')")]
            if columns[:2] == ["src", "dst"]:
                optimal = True
                break
    finally:
        conn.close()
    assert optimal, "No covering index beginning with edges(src, dst) was created for the triangle joins."

def test_program_generates_outputs_from_database():
    assert os.path.isfile(SOURCE_PATH), f"C source {SOURCE_PATH} is missing."
    assert os.path.isfile(EXECUTABLE_PATH), f"Executable {EXECUTABLE_PATH} is missing."
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "triangle_analyzer is not a compiled ELF executable."

    # Execute the submitted artifact after deleting both outputs, then validate them.
    run_clean(EXECUTABLE_PATH)
    assert_generated_outputs()

    # Rebuild the submitted C source so the checked behavior must be present in that source.
    rebuilt = "/tmp/triangle_analyzer_rebuilt"
    subprocess.run(
        ["gcc", "-O2", "-o", rebuilt, SOURCE_PATH, "-lsqlite3"],
        check=True,
        timeout=30,
    )

    # Exercise the rebuilt program on a private database/index variation. The random
    # index name must appear in the literal SQLite plan, preventing a fabricated plan,
    # and the added triangle hub prevents a hard-coded analytics answer.
    backup = tempfile.mktemp(prefix="graph-backup-", suffix=".db")
    shutil.copy2(DB_PATH, backup)
    try:
        conn = sqlite3.connect(DB_PATH)
        try:
            current = conn.execute(QUERY).fetchone()
            current_max = int(current[1]) if current else 0
            max_node = conn.execute("SELECT COALESCE(MAX(MAX(src, dst)), 0) FROM edges").fetchone()[0]

            index_rows = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='edges'"
            ).fetchall()
            for (name,) in index_rows:
                conn.execute('DROP INDEX "' + name.replace('"', '""') + '"')
            private_index = "idx_verify_" + secrets.token_hex(8)
            conn.execute(f'CREATE INDEX "{private_index}" ON edges(src, dst)')

            hub = max_node + 1000 + secrets.randbelow(1000000)
            cycle_count = 7
            multiplicity = max(3, math.ceil(((current_max + 1) / cycle_count) ** (1 / 3)))
            while cycle_count * multiplicity ** 3 <= current_max:
                multiplicity += 1
            rows = []
            for i in range(cycle_count):
                b = hub + 2 * i + 1
                c = hub + 2 * i + 2
                rows.extend([(hub, b)] * multiplicity)
                rows.extend([(b, c)] * multiplicity)
                rows.extend([(c, hub)] * multiplicity)
            conn.executemany("INSERT INTO edges(src, dst) VALUES (?, ?)", rows)
            conn.commit()
        finally:
            conn.close()

        run_clean(rebuilt)
        assert read_result() == expected_result(), "The rebuilt C program did not query the changed database."
        plan = read_plan()
        assert plan == expected_plan(), "The rebuilt C program did not emit literal EXPLAIN QUERY PLAN details."
        assert any(private_index in line for line in plan), "The private SQLite index name is absent from the generated plan."
    finally:
        shutil.copy2(backup, DB_PATH)
        os.remove(backup)
        # Leave the requested outputs corresponding to the agent's final database.
        subprocess.run([rebuilt], check=False, timeout=30)

def test_query_plan_output():
    assert os.path.exists(QUERY_PLAN_PATH), f"Query plan output {QUERY_PLAN_PATH} is missing."
    with open(QUERY_PLAN_PATH, "r") as f:
        content = f.read().upper()

    assert "SEARCH" in content, "Query plan does not indicate index usage (missing 'SEARCH')."
    assert "SCAN TABLE EDGES" not in content, "Query plan indicates full table scan on 'edges' (found 'SCAN TABLE edges')."
    assert read_plan() == expected_plan(), "Query plan is not the literal detail output of EXPLAIN QUERY PLAN."

def test_max_triangle_output():
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} missing."

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute(QUERY)
    result = c.fetchone()
    conn.close()

    assert result is not None, "Database has no triangles."
    expected_output = f"{result[0]},{result[1]}"

    assert os.path.exists(MAX_TRIANGLE_PATH), f"Max triangle output {MAX_TRIANGLE_PATH} is missing."
    with open(MAX_TRIANGLE_PATH, "r") as f:
        content = f.read().strip()

    assert content == expected_output, f"Expected output '{expected_output}', but got '{content}'."

def test_executable_exists():
    assert os.path.exists(EXECUTABLE_PATH), f"Executable {EXECUTABLE_PATH} is missing."
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"File {EXECUTABLE_PATH} is not executable."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
