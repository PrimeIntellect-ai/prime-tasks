#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

HOME = "/home/user"
DB = f"{HOME}/graph.db"
CPP = f"{HOME}/project_graph.cpp"
BIN = f"{HOME}/project_graph"
OUTPUT = f"{HOME}/output.csv"
SQL_FILE = f"{HOME}/fixed_query.sql"
PLAN_FILE = f"{HOME}/query_plan.txt"


def projected_rows(db_path):
    with sqlite3.connect(db_path) as conn:
        return conn.execute("""
            SELECT e1.src, e2.dst
            FROM Edges AS e1
            JOIN Edges AS e2 ON e1.dst = e2.src
            WHERE e1.type = 'friend'
              AND e2.type = 'friend'
              AND e1.src <> e2.dst
              AND NOT EXISTS (
                  SELECT 1
                  FROM Edges AS direct
                  WHERE direct.src = e1.src
                    AND direct.dst = e2.dst
                    AND direct.type = 'friend'
              )
            ORDER BY e1.src ASC, e2.dst ASC
        """).fetchall()


def expected_csv(db_path):
    rows = projected_rows(db_path)
    return "src,dst\n" + "\n".join(f"{src},{dst}" for src, dst in rows)


def compile_program():
    assert os.path.isfile(CPP), f"{CPP} is missing."
    if os.path.exists(BIN):
        os.remove(BIN)
    result = subprocess.run(
        ["g++", "-O3", CPP, "-lsqlite3", "-o", BIN],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"Compilation failed:\n{result.stderr}"
    assert os.path.isfile(BIN) and os.access(BIN, os.X_OK), "Compiled executable is missing."


def run_program():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [BIN], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, (
        f"The compiled program exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is missing after executing the program."


def read_output():
    with open(OUTPUT, "r", newline="") as f:
        return f.read().strip()


def test_output_csv_content_from_executed_program():
    compile_program()
    expected = expected_csv(DB)
    run_program()
    content = read_output()
    assert content == expected, (
        f"The content of {OUTPUT} does not match the graph projection. "
        f"Got:\n{content}\nExpected:\n{expected}"
    )


def test_cpp_file_modifications():
    assert os.path.isfile(CPP), f"{CPP} is missing."
    with open(CPP, "r") as f:
        content = f.read().lower()

    assert "limit" in content and "offset" in content, (
        "The C++ program does not appear to implement pagination using LIMIT and OFFSET."
    )
    assert re.search(r'\b(while|for)\b', content), (
        "The C++ program does not appear to contain a loop construct for pagination."
    )
    assert re.search(r'limit\s+5\s+offset\s+\?', content, re.I | re.S), (
        "The C++ query must use LIMIT 5 OFFSET ?."
    )
    assert re.search(r'\bsqlite3_bind_(?:int|int64)\s*\(', content), (
        "The C++ program does not bind the OFFSET parameter."
    )


def test_program_handles_more_than_one_page_on_an_independent_database():
    fd, backup = tempfile.mkstemp(prefix="graph-backup-", suffix=".db")
    os.close(fd)
    shutil.copy2(DB, backup)

    try:
        os.remove(DB)
        with sqlite3.connect(DB) as conn:
            conn.executescript("""
                CREATE TABLE Nodes (id INTEGER PRIMARY KEY, name TEXT);
                CREATE TABLE Edges (src INTEGER, dst INTEGER, type TEXT);
                INSERT INTO Nodes VALUES
                    (10,'n10'),(11,'n11'),(12,'n12'),(13,'n13'),(14,'n14'),
                    (15,'n15'),(16,'n16'),(17,'n17'),(18,'n18'),(19,'n19'),(20,'n20');
                INSERT INTO Edges VALUES
                    (10,11,'friend'),(11,12,'friend'),(12,13,'friend'),
                    (13,14,'friend'),(14,15,'friend'),(15,16,'friend'),
                    (16,17,'friend'),(17,18,'friend'),(18,19,'friend'),
                    (19,20,'friend'),
                    (10,12,'friend'),
                    (11,15,'coworker'),(15,20,'blocked');
            """)

        expected = expected_csv(DB)
        assert len(projected_rows(DB)) > 5, "Verifier fixture must exercise multiple pages."
        run_program()
        assert read_output() == expected, (
            "The executable did not correctly compute and paginate an independent graph."
        )
    finally:
        if os.path.exists(DB):
            os.remove(DB)
        shutil.copy2(backup, DB)
        os.remove(backup)
        # Leave the required output corresponding to the task's original database.
        run_program()


def load_fixed_sql():
    assert os.path.isfile(SQL_FILE), f"{SQL_FILE} is missing."
    with open(SQL_FILE, "r") as f:
        sql = f.read().strip()
    assert sql, f"{SQL_FILE} is empty."
    return sql.rstrip().rstrip(";").strip()


def execute_fixed_query(sql):
    placeholders = sql.count("?")
    with sqlite3.connect(DB) as conn:
        if placeholders == 0:
            return conn.execute(sql).fetchall()
        assert placeholders == 1 and re.search(r'limit\s+5\s+offset\s+\?', sql, re.I | re.S), (
            "The fixed query may only use the required OFFSET placeholder."
        )
        rows = []
        offset = 0
        while True:
            page = conn.execute(sql, (offset,)).fetchall()
            if not page:
                break
            rows.extend(page)
            offset += 5
        return rows


def test_fixed_query_sql_exists_and_is_correct():
    sql = load_fixed_sql()
    actual = execute_fixed_query(sql)
    expected = projected_rows(DB)
    assert actual == expected, (
        f"{SQL_FILE} does not produce the required ordered second-degree edges. "
        f"Got {actual}, expected {expected}."
    )


def test_query_plan_exists_and_content():
    assert os.path.isfile(PLAN_FILE), f"{PLAN_FILE} is missing."
    with open(PLAN_FILE, "r") as f:
        content = f.read().upper()

    assert "SCAN" in content or "SEARCH" in content, (
        f"The query plan in {PLAN_FILE} does not contain expected EXPLAIN QUERY PLAN "
        "output like SCAN or SEARCH."
    )

    sql = load_fixed_sql()
    params = (0,) if sql.count("?") == 1 else ()
    with sqlite3.connect(DB) as conn:
        plan_rows = conn.execute("EXPLAIN QUERY PLAN " + sql, params).fetchall()

    normalized_plan = " ".join(content.split())
    assert plan_rows, "EXPLAIN QUERY PLAN returned no rows for the fixed query."
    for row in plan_rows:
        detail = " ".join(str(row[3]).upper().split())
        assert detail in normalized_plan, (
            f"{PLAN_FILE} does not match EXPLAIN QUERY PLAN for {SQL_FILE}; "
            f"missing plan detail: {row[3]}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
