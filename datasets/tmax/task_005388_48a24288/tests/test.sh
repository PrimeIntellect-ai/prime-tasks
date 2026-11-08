#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import random
import re
import sqlite3
import subprocess
import time
from collections import defaultdict, deque

import pytest

QUERY_PATH = "/home/user/query.sql"
CSV_PATH = "/home/user/projected_graph.csv"
DB_PATH = "/app/research.db"
BIN_PATH = "/home/user/path_filter"


def load_query():
    assert os.path.isfile(QUERY_PATH), f"Missing SQL query at {QUERY_PATH}"
    with open(QUERY_PATH, "r", encoding="utf-8") as f:
        raw = f.read()
    assert raw.strip(), "query.sql is empty"

    # Formatting/output commands are allowed in an sqlite shell script, but are
    # irrelevant when testing the SQL against isolated databases.
    allowed_dot_commands = {
        ".headers", ".mode", ".separator", ".nullvalue", ".output", ".once"
    }
    sql_lines = []
    for line in raw.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("."):
            command = stripped.split(None, 1)[0].lower()
            assert command in allowed_dot_commands, f"Unsupported sqlite command in query.sql: {command}"
            continue
        sql_lines.append(line)
    sql = "\n".join(sql_lines).strip()
    assert sql, "query.sql contains no SQL query"

    # Check the required SQL constructs after removing comments and literals so
    # keywords merely written in a comment do not satisfy the requirement.
    structural = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    structural = re.sub(r"--[^\n]*", " ", structural)
    structural = re.sub(r"'(?:''|[^'])*'", "''", structural)
    assert re.search(r"\bWITH\s+RECURSIVE\b", structural, flags=re.I), \
        "query.sql must use a recursive CTE"
    assert re.search(r"\bOVER\s*\(", structural, flags=re.I), \
        "query.sql must use a window function"
    assert re.search(r"\bPARTITION\s+BY\b", structural, flags=re.I), \
        "window ranking must be partitioned"
    return sql


def execute_query(db_path, sql):
    conn = sqlite3.connect(db_path)
    deadline = time.monotonic() + 5.0

    def progress():
        return 1 if time.monotonic() > deadline else 0

    conn.set_progress_handler(progress, 10000)
    conn.execute("PRAGMA query_only=ON")
    try:
        cur = conn.cursor()
        # sqlite3.execute rejects additional SQL statements. The submitted
        # artifact must be the single result-producing query requested.
        cur.execute(sql)
        assert cur.description is not None, "query.sql does not produce a result set"
        columns = [d[0] for d in cur.description]
        rows = cur.fetchall()
        return columns, rows
    finally:
        conn.close()


def csv_value(value):
    return "" if value is None else str(value)


def read_csv(path):
    assert os.path.exists(path), f"Missing CSV output at {path}"
    with open(path, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        rows = list(reader)
    return header, rows


def test_sql_and_csv_output():
    # Preserve the original independent computation and assertions.
    assert os.path.exists(CSV_PATH), f"Missing CSV output at {CSV_PATH}"
    assert os.path.exists(DB_PATH), f"Missing database at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # The supplied fixture must not be erased or rewritten to make the expected
    # output vacuous.
    cursor.execute("SELECT id, title, year, citations, is_deleted FROM papers ORDER BY id")
    assert cursor.fetchall() == [(4582, "Root Paper", 2020, 100, 0)], \
        "The supplied papers table was modified"
    cursor.execute("SELECT source_id, target_id, is_deleted FROM edges ORDER BY rowid")
    assert cursor.fetchall() == [(4582, 1234, 0)], "The supplied edges table was modified"

    cursor.execute("SELECT source_id, target_id FROM edges WHERE is_deleted = 0")
    edges = cursor.fetchall()
    cursor.execute("SELECT id, title, year, citations FROM papers WHERE is_deleted = 0")
    papers = {row[0]: {'title': row[1], 'year': row[2], 'citations': row[3]} for row in cursor.fetchall()}
    conn.close()

    adj = {}
    for src, tgt in edges:
        adj.setdefault(src, []).append(tgt)

    visited = set()
    queue = [(4582, 0)]
    while queue:
        node, depth = queue.pop(0)
        if node not in visited:
            visited.add(node)
            if depth < 3:
                for neighbor in adj.get(node, []):
                    queue.append((neighbor, depth + 1))

    subgraph_papers = []
    for node in visited:
        if node in papers:
            p = papers[node]
            subgraph_papers.append((node, p['title'], p['year'], p['citations']))

    by_year = {}
    for p in subgraph_papers:
        by_year.setdefault(p[2], []).append(p)

    ranked_papers = []
    for y, items in by_year.items():
        items.sort(key=lambda x: x[3], reverse=True)
        for i, item in enumerate(items):
            ranked_papers.append((item[0], item[1], item[2], item[3], i + 1))
    ranked_papers.sort(key=lambda x: (x[2], x[4]))
    expected_top_50 = ranked_papers[:50]

    header, rows = read_csv(CSV_PATH)
    assert len(rows) == len(expected_top_50), \
        f"Expected {len(expected_top_50)} rows in CSV, got {len(rows)}"
    for i, (actual, expected) in enumerate(zip(rows, expected_top_50)):
        actual_str = ",".join(actual)
        assert str(expected[0]) in actual_str, \
            f"Row {i+1} mismatch: expected paper ID {expected[0]} in {actual}"

    # Additionally execute the submitted artifact and require the saved CSV to
    # be exactly its result, rather than accepting an ID substring.
    sql = load_query()
    columns, query_rows = execute_query(DB_PATH, sql)
    assert header == columns, f"CSV header {header!r} does not match query columns {columns!r}"
    expected_csv_rows = [[csv_value(v) for v in row] for row in query_rows]
    assert rows == expected_csv_rows, "projected_graph.csv is not the exact output of query.sql"


def make_dynamic_database(path):
    rng = random.SystemRandom()
    ids = rng.sample(range(100000, 9000000), 90)
    root = 4582
    level1 = ids[:8]
    level2 = ids[8:28]
    level3 = ids[28:68]
    level4 = ids[68:76]
    hidden_deleted_edge = ids[76]
    deleted_paper = ids[77]

    conn = sqlite3.connect(path)
    conn.executescript("""
        CREATE TABLE papers(id INTEGER PRIMARY KEY, title TEXT, year INTEGER, citations INTEGER, is_deleted INTEGER);
        CREATE TABLE edges(source_id INTEGER, target_id INTEGER, is_deleted INTEGER);
        CREATE INDEX idx_edges_source ON edges(source_id);
    """)

    discovered = [root] + level1 + level2 + level3
    all_active = discovered + level4 + [hidden_deleted_edge]
    paper_rows = []
    for i, pid in enumerate(all_active):
        year = 2016 + (i % 6)
        citations = 500000 - (i * 97) - (pid % 31)
        title = f"Generated paper {pid}, cohort {year}"
        paper_rows.append((pid, title, year, citations, 0))
    paper_rows.append((deleted_paper, "Deleted paper", 2015, 999999, 1))
    conn.executemany("INSERT INTO papers VALUES (?, ?, ?, ?, ?)", paper_rows)

    edge_rows = []
    edge_rows.extend((root, child, 0) for child in level1)
    edge_rows.extend((level1[i % len(level1)], child, 0) for i, child in enumerate(level2))
    edge_rows.extend((level2[i % len(level2)], child, 0) for i, child in enumerate(level3))
    edge_rows.extend((level3[i % len(level3)], child, 0) for i, child in enumerate(level4))
    # Duplicate routes and cycles must not duplicate final papers.
    edge_rows.extend([
        (level1[0], level2[1], 0),
        (level2[0], level3[1], 0),
        (level2[2], root, 0),
        (level3[3], level1[1], 0),
    ])
    # These records must never add their targets to the result.
    edge_rows.append((root, hidden_deleted_edge, 1))
    edge_rows.append((root, deleted_paper, 0))
    conn.executemany("INSERT INTO edges VALUES (?, ?, ?)", edge_rows)
    conn.commit()

    papers = {r[0]: r for r in paper_rows if r[4] == 0}
    adj = defaultdict(list)
    for src, target, deleted in edge_rows:
        if deleted == 0:
            adj[src].append(target)

    seen = set()
    queue = deque([(root, 0)])
    while queue:
        node, depth = queue.popleft()
        if node in seen:
            continue
        seen.add(node)
        if depth < 3:
            queue.extend((target, depth + 1) for target in adj[node])

    selected = [papers[node] for node in seen if node in papers]
    by_year = defaultdict(list)
    for row in selected:
        by_year[row[2]].append(row)

    expected = []
    for year, year_rows in by_year.items():
        year_rows.sort(key=lambda r: r[3], reverse=True)
        for rank, row in enumerate(year_rows, 1):
            expected.append((row[0], row[1], row[2], row[3], rank))
    expected.sort(key=lambda r: (r[2], r[4]))
    conn.close()
    return expected[:50]


def test_query_on_unseen_graph(tmp_path):
    sql = load_query()
    db = str(tmp_path / "unseen.db")
    expected = make_dynamic_database(db)
    columns, rows = execute_query(db, sql)

    lowered = [str(c).strip().lower() for c in columns]
    assert len(lowered) == len(set(lowered)), "Query output has duplicate column names"

    def find_column(*names):
        for name in names:
            if name in lowered:
                return lowered.index(name)
        pytest.fail(f"Query result is missing required column: {names[0]}")

    id_i = find_column("id", "paper_id")
    title_i = find_column("title")
    year_i = find_column("year")
    citations_i = find_column("citations")
    rank_i = find_column("rank")

    actual = [
        (row[id_i], row[title_i], row[year_i], row[citations_i], row[rank_i])
        for row in rows
    ]
    assert actual == expected, \
        "query.sql failed traversal, deletion filtering, ranking, ordering, or top-50 pagination on an unseen graph"


def test_path_filter_executable():
    assert os.path.exists(BIN_PATH), f"Missing executable at {BIN_PATH}"
    assert os.path.isfile(BIN_PATH), f"{BIN_PATH} is not a regular file"
    assert os.access(BIN_PATH, os.X_OK), f"{BIN_PATH} is not executable"
    with open(BIN_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "path_filter must be a compiled executable"


def test_adversarial_corpus_clean():
    clean_dir = "/app/corpus/clean"
    if not os.path.exists(clean_dir):
        pytest.skip(f"Clean corpus dir {clean_dir} not found")
    failed_files = []
    total_files = 0
    for fname in os.listdir(clean_dir):
        total_files += 1
        fpath = os.path.join(clean_dir, fname)
        with open(fpath, 'rb') as f:
            input_data = f.read()
        proc = subprocess.run([BIN_PATH], input=input_data, capture_output=True, timeout=10)
        if proc.returncode != 0 or proc.stdout != input_data:
            failed_files.append(fname)
    assert not failed_files, f"{len(failed_files)} of {total_files} clean modified/rejected: {failed_files[:5]}"


def test_adversarial_corpus_evil():
    evil_dir = "/app/corpus/evil"
    if not os.path.exists(evil_dir):
        pytest.skip(f"Evil corpus dir {evil_dir} not found")
    failed_files = []
    total_files = 0
    for fname in os.listdir(evil_dir):
        total_files += 1
        fpath = os.path.join(evil_dir, fname)
        with open(fpath, 'rb') as f:
            input_data = f.read()
        proc = subprocess.run([BIN_PATH], input=input_data, capture_output=True, timeout=10)
        if proc.returncode != 0 or proc.stdout.strip():
            failed_files.append(fname)
    assert not failed_files, f"{len(failed_files)} of {total_files} evil bypassed: {failed_files[:5]}"


def test_path_filter_on_unseen_mixed_corpus():
    rng = random.SystemRandom()
    lines = []
    expected = []
    for i in range(2500):
        length = rng.randint(1, 45)
        values = rng.sample(range(1, 2000000000), length)
        clean = (i % 3) != 0
        if not clean:
            duplicate_from = rng.randrange(length)
            duplicate_at = rng.randrange(length + 1)
            values.insert(duplicate_at, values[duplicate_from])
        line = ",".join(str(v) for v in values).encode("ascii")
        # Exercise both newline-terminated input and a final unterminated line.
        if i != 2499:
            line += b"\n"
        lines.append(line)
        if clean:
            expected.append(line)

    input_data = b"".join(lines)
    expected_output = b"".join(expected)
    proc = subprocess.run([BIN_PATH], input=input_data, capture_output=True, timeout=15)
    assert proc.returncode == 0, f"path_filter exited with status {proc.returncode}: {proc.stderr[:200]!r}"
    assert proc.stdout == expected_output, \
        "path_filter did not exactly preserve all unseen acyclic lines and remove all unseen cyclic lines"

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
