#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import sqlite3
import subprocess
from collections import Counter

import pytest

SCRIPT = "/home/user/find_paths.sh"
PAGES = "/home/user/pages.csv"
LINKS = "/home/user/links.csv"
DB = "/home/user/graph.db"
OUTPUT = "/home/user/reachable.txt"
SCHEMA = "/home/user/schema.txt"


def write_csv(path, header, rows):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)


def explicit_indexes(conn, table):
    indexes = []
    for row in conn.execute(f"PRAGMA index_list('{table}')"):
        name = row[1]
        sql_row = conn.execute(
            "SELECT sql FROM sqlite_master WHERE type='index' AND name=?", (name,)
        ).fetchone()
        if not sql_row or sql_row[0] is None:
            continue
        columns = [r[2].lower() for r in conn.execute(f"PRAGMA index_info('{name}')")]
        indexes.append((name, columns))
    return indexes


def run_case(page_rows, link_rows, expected_urls):
    write_csv(PAGES, ["page_id", "url", "topic"], page_rows)
    write_csv(LINKS, ["source_id", "target_id"], link_rows)

    for path in (DB, OUTPUT, SCHEMA):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [SCRIPT], cwd="/home/user", text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, (
        f"Script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.isfile(DB), f"Database not found at {DB}"
    assert os.path.isfile(OUTPUT), f"Output file not found at {OUTPUT}"
    assert os.path.isfile(SCHEMA), f"Schema file not found at {SCHEMA}"

    with open(OUTPUT) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines == sorted(expected_urls), (
        f"Contents of {OUTPUT} do not match the expected output. Got: {lines}"
    )

    with open(SCHEMA) as f:
        schema_text = f.read()
    schema_upper = schema_text.upper()
    assert "CREATE INDEX" in schema_upper, f"No CREATE INDEX statements found in {SCHEMA}"
    assert "CREATE TABLE" in schema_upper
    assert "PAGES" in schema_upper and "LINKS" in schema_upper

    conn = sqlite3.connect(DB)
    try:
        assert conn.execute("PRAGMA integrity_check").fetchone()[0].lower() == "ok"

        tables = {
            row[0]
            for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )
        }
        assert {"pages", "links"}.issubset(tables), f"Missing required tables: {tables}"

        page_columns = {r[1].lower() for r in conn.execute("PRAGMA table_info(pages)")}
        link_columns = {r[1].lower() for r in conn.execute("PRAGMA table_info(links)")}
        assert {"page_id", "url", "topic"}.issubset(page_columns)
        assert {"source_id", "target_id"}.issubset(link_columns)

        actual_pages = Counter(
            tuple(str(v) for v in row)
            for row in conn.execute("SELECT page_id, url, topic FROM pages")
        )
        actual_links = Counter(
            tuple(str(v) for v in row)
            for row in conn.execute("SELECT source_id, target_id FROM links")
        )
        assert actual_pages == Counter(tuple(map(str, row)) for row in page_rows)
        assert actual_links == Counter(tuple(map(str, row)) for row in link_rows)

        page_indexes = explicit_indexes(conn, "pages")
        link_indexes = explicit_indexes(conn, "links")
        assert any(cols and cols[0] in {"page_id", "url"} for _, cols in page_indexes), (
            "No explicit index on a pages lookup/join column"
        )
        assert any(cols and cols[0] == "source_id" for _, cols in link_indexes), (
            "No index beginning with links.source_id"
        )
        assert any(cols and cols[0] == "target_id" for _, cols in link_indexes), (
            "No index beginning with links.target_id"
        )

        for name, _ in page_indexes + link_indexes:
            assert name.upper() in schema_upper, (
                f"Actual database index {name} is missing from {SCHEMA}"
            )
    finally:
        conn.close()


def test_complete_solution():
    assert os.path.isfile(SCRIPT), f"Script not found at {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Script at {SCRIPT} is not executable"

    with open(SCRIPT, errors="replace") as f:
        script_text = f.read().upper()
    assert "SQLITE3" in script_text, "The script does not invoke sqlite3"
    assert "WITH RECURSIVE" in script_text, "The script does not contain a recursive CTE"

    original_pages = [
        (1, "http://example.com/start", "Home"),
        (2, "http://example.com/a", "AI"),
        (3, "http://example.com/b", "Data Querying"),
        (4, "http://example.com/c", "Data Querying"),
        (5, "http://example.com/d", "Bash"),
        (6, "http://example.com/e", "Data Querying"),
        (7, "http://example.com/f", "Data Querying"),
    ]
    original_links = [(1, 2), (2, 3), (1, 5), (5, 4), (4, 6), (3, 6), (6, 7)]
    run_case(
        original_pages,
        original_links,
        [
            "http://example.com/b",
            "http://example.com/c",
            "http://example.com/e",
        ],
    )

    token = secrets.token_hex(8)
    base = f"http://{token}.invalid"
    dynamic_pages = [
        (101, "http://example.com/start", "Home"),
        (205, f"{base}/z", "Data Querying"),
        (309, f"{base}/bridge", "Other"),
        (412, f"{base}/a", "Data Querying"),
        (518, f"{base}/m", "Data Querying"),
        (623, f"{base}/too-far", "Data Querying"),
        (777, f"{base}/wrong-topic", "AI"),
        (888, f"{base}/unreachable", "Data Querying"),
    ]
    dynamic_links = [
        (101, 205),
        (101, 309),
        (309, 412),
        (205, 412),
        (412, 518),
        (518, 623),
        (101, 777),
        (412, 309),
    ]
    run_case(
        dynamic_pages,
        dynamic_links,
        [f"{base}/a", f"{base}/m", f"{base}/z"],
    )
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
