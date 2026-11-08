#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import collections
import os
import random
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

SOURCE = "/home/user/detect.c"
DETECT = "/home/user/detect"
CSV = "/home/user/wait_for.csv"
QUERY = "/home/user/query.sql"
OUTPUT = "/home/user/deadlocks.txt"


def test_original_assertions():
    assert os.path.isfile(SOURCE), f"Missing C source file: {SOURCE}"
    assert os.path.isfile(DETECT), f"Missing compiled executable: {DETECT}"
    assert os.access(DETECT, os.X_OK), f"File is not executable: {DETECT}"
    assert os.path.isfile(QUERY), f"Missing generated SQL script: {QUERY}"
    assert os.path.isfile(OUTPUT), f"Missing output file: {OUTPUT}"

    expected_lines = ["1", "2", "3", "7", "8"]
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert actual_lines == expected_lines, (
        f"Content of {OUTPUT} does not match expected deadlocks. "
        f"Expected: {expected_lines}, Got: {actual_lines}"
    )

    with open(DETECT, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{DETECT} is not a compiled ELF executable"


def expected_deadlocks(edges):
    adjacency = collections.defaultdict(list)
    nodes = set()
    for waiting, holding in edges:
        adjacency[waiting].append(holding)
        nodes.add(waiting)
        nodes.add(holding)

    answer = []
    for start in nodes:
        frontier = {start}
        found = False
        for _depth in range(1, 6):
            frontier = {nxt for node in frontier for nxt in adjacency.get(node, [])}
            if start in frontier:
                found = True
                break
            if not frontier:
                break
        if found:
            answer.append(start)
    return sorted(answer)


def remove_comments(sql):
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    sql = re.sub(r"--[^\n]*", " ", sql)
    return sql


def split_statements(sql):
    statements = []
    buf = ""
    for ch in sql:
        buf += ch
        if ch == ";" and sqlite3.complete_statement(buf):
            if remove_comments(buf).strip():
                statements.append(buf.strip())
            buf = ""
    if remove_comments(buf).strip():
        statements.append(buf.strip())
    return statements


def validate_generated_sql(sql, db_path, expected_edges):
    cleaned = remove_comments(sql)
    assert re.search(r"\bCREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?wait_for\b", cleaned, re.I), \
        "query.sql must create the wait_for table"
    assert re.search(r"\bINSERT\s+INTO\s+wait_for\b", cleaned, re.I), \
        "query.sql must insert the CSV rows"
    assert re.search(r"\bWITH\s+RECURSIVE\b", cleaned, re.I), \
        "query.sql must use a recursive CTE"

    statements = split_statements(sql)
    result_statements = []
    recursive_statements = []
    for statement in statements:
        normalized = remove_comments(statement).lstrip()
        if re.match(r"SELECT\b", normalized, re.I) or re.match(r"WITH\b", normalized, re.I):
            result_statements.append(statement)
        if re.match(r"WITH\s+RECURSIVE\b", normalized, re.I):
            recursive_statements.append(statement)

    assert len(recursive_statements) == 1, "query.sql must contain one recursive CTE query"
    assert result_statements == recursive_statements, \
        "The sole result-producing statement must be the recursive CTE query"

    con = sqlite3.connect(db_path)
    try:
        schema = con.execute("PRAGMA table_info(wait_for)").fetchall()
        assert [(row[1], row[2].upper()) for row in schema] == [
            ("tx_waiting", "INTEGER"), ("tx_holding", "INTEGER")
        ], f"Incorrect wait_for schema: {schema}"

        actual_edges = con.execute(
            "SELECT tx_waiting, tx_holding FROM wait_for"
        ).fetchall()
        assert collections.Counter(actual_edges) == collections.Counter(expected_edges), (
            f"query.sql did not insert exactly the CSV rows; expected {expected_edges}, "
            f"got {actual_edges}"
        )

        plan = con.execute(
            "EXPLAIN QUERY PLAN " + recursive_statements[0].rstrip().rstrip(";")
        ).fetchall()
        descriptions = "\n".join(str(row[3]).upper() for row in plan)
        assert "RECURSIVE STEP" in descriptions, \
            f"The result query does not execute a recursive CTE. Plan:\n{descriptions}"
        assert "SCAN" in descriptions, \
            f"The result query does not scan the recursive result. Plan:\n{descriptions}"
    finally:
        con.close()


def run_case(program, edges):
    with open(CSV, "w") as f:
        f.write("tx_waiting,tx_holding\n")
        for waiting, holding in edges:
            f.write(f"{waiting},{holding}\n")

    if os.path.exists(QUERY):
        os.unlink(QUERY)

    subprocess.run([program], cwd="/home/user", check=True, timeout=10)
    assert os.path.isfile(QUERY), f"{program} did not generate {QUERY}"

    with open(QUERY, "r") as f:
        sql = f.read()
    assert sql.strip(), "Generated query.sql is empty"

    fd, db_path = tempfile.mkstemp(prefix="deadlock_verify_", suffix=".db")
    os.close(fd)
    os.unlink(db_path)
    try:
        result = subprocess.run(
            ["sqlite3", db_path], input=sql, text=True,
            capture_output=True, timeout=10
        )
        assert result.returncode == 0, f"SQLite rejected query.sql: {result.stderr}"
        assert not result.stderr.strip(), f"SQLite produced errors: {result.stderr}"

        lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        try:
            actual = [int(line) for line in lines]
        except ValueError:
            raise AssertionError(f"SQL output contains non-integer or extra data: {lines}")
        expected = expected_deadlocks(edges)
        assert actual == expected, f"Expected deadlocks {expected}, got {actual}"

        validate_generated_sql(sql, db_path, edges)
    finally:
        if os.path.exists(db_path):
            os.unlink(db_path)


def make_cases():
    base = secrets.randbelow(500000) + 100000
    ids = [base + 17 * i for i in range(20)]

    structured = [
        (ids[0], ids[0]),
        (ids[1], ids[2]), (ids[2], ids[1]),
        (ids[3], ids[4]), (ids[4], ids[5]), (ids[5], ids[6]),
        (ids[6], ids[7]), (ids[7], ids[3]),
        (ids[8], ids[9]), (ids[9], ids[10]), (ids[10], ids[11]),
        (ids[11], ids[12]), (ids[12], ids[13]), (ids[13], ids[8]),
        (ids[14], ids[15]), (ids[15], ids[16]),
    ]

    rng = random.SystemRandom()
    random_graph = []
    random_ids = ids[:12]
    for _ in range(22):
        random_graph.append((rng.choice(random_ids), rng.choice(random_ids)))

    rng.shuffle(structured)
    rng.shuffle(random_graph)
    return [structured, random_graph]


def test_program_behavior():
    original_csv = open(CSV, "rb").read()
    compiled = "/tmp/detect_from_source"
    try:
        build = subprocess.run(
            ["gcc", "-o", compiled, SOURCE], text=True,
            capture_output=True, timeout=20
        )
        assert build.returncode == 0, f"detect.c does not compile with gcc: {build.stderr}"

        cases = make_cases()
        for program in (DETECT, compiled):
            for edges in cases:
                run_case(program, edges)
    finally:
        with open(CSV, "wb") as f:
            f.write(original_csv)
        if os.path.exists(compiled):
            os.unlink(compiled)
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
