#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import random
import re
import sqlite3
import subprocess
import tokenize

import pytest

SCRIPT_PATH = '/home/user/export_graph.py'
JSON_PATH = '/home/user/graph.json'
DB_PATH = '/home/user/citations.db'


def run_script(start_year, end_year):
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    result = subprocess.run(
        ['python3', SCRIPT_PATH, str(start_year), str(end_year)],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Script failed to execute. Stderr: {result.stderr}"
    assert os.path.isfile(JSON_PATH), f"Output file not found at {JSON_PATH} after running the script."
    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} does not contain valid JSON.")


def test_script_exists():
    """Test that the required script exists."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"


def test_script_uses_window_function():
    """Test that the script uses an SQL Window Function."""
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        content = f.read().upper()
    assert 'OVER' in content, "The script must use an SQL Window Function (e.g., OVER clause) to deduplicate citations."


def test_window_function_is_not_only_in_a_comment():
    """Require recognizable window-function syntax in executable source or an SQL string."""
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    tokens = tokenize.generate_tokens(io.StringIO(source).readline)
    without_comments = ''.join(
        token.string for token in tokens if token.type != tokenize.COMMENT
    ).upper()
    pattern = re.compile(
        r'(?:ROW_NUMBER|RANK)\s*\(\s*\)\s*OVER\s*\('
        r'|MAX\s*\([^)]*\)\s*OVER\s*\(',
        re.DOTALL,
    )
    assert pattern.search(without_comments), (
        "The script must contain SQL ROW_NUMBER(), RANK(), or MAX() OVER() syntax; "
        "mentioning OVER only in a comment is insufficient."
    )


def test_script_execution_and_output():
    """Retain the original fixed-case execution and exact-output assertions."""
    data = run_script(2015, 2020)

    assert "nodes" in data, "JSON output is missing the 'nodes' key."
    assert "edges" in data, "JSON output is missing the 'edges' key."

    expected_nodes = [
        {"id": 1, "title": "Paper A", "year": 2015},
        {"id": 2, "title": "Paper B", "year": 2016},
        {"id": 3, "title": "Paper C", "year": 2018}
    ]
    expected_edges = [
        {"source": 2, "target": 1, "citation_date": "2016-05-05"},
        {"source": 3, "target": 1, "citation_date": "2018-02-02"},
        {"source": 3, "target": 2, "citation_date": "2018-03-03"}
    ]

    assert data["nodes"] == expected_nodes, f"Nodes do not match expected output. Got: {data['nodes']}"
    assert data["edges"] == expected_edges, f"Edges do not match expected output. Got: {data['edges']}"


def expected_graph(papers, citations, start_year, end_year):
    selected = {
        paper_id: {"id": paper_id, "title": title, "year": year}
        for paper_id, title, year in papers
        if start_year <= year <= end_year
    }

    latest = {}
    for source, target, citation_date in citations:
        key = (source, target)
        if key not in latest or citation_date > latest[key]:
            latest[key] = citation_date

    edges = [
        {"source": source, "target": target, "citation_date": citation_date}
        for (source, target), citation_date in latest.items()
        if source in selected and target in selected
    ]
    edges.sort(key=lambda edge: (edge["source"], edge["target"]))

    connected = {
        paper_id
        for edge in edges
        for paper_id in (edge["source"], edge["target"])
    }
    nodes = [selected[paper_id] for paper_id in sorted(connected)]
    return {"nodes": nodes, "edges": edges}


def test_dynamic_database_and_multiple_ranges():
    """Exercise database-dependent projection, deduplication, filtering, and ordering."""
    with open(DB_PATH, 'rb') as f:
        original_db = f.read()

    rng = random.SystemRandom()
    ids = rng.sample(range(1000, 900000), 7)
    base_year = rng.randint(1980, 2035)
    titles = [f"Dynamic Paper {rng.randrange(10**12):012d}" for _ in ids]
    papers = [
        (ids[0], titles[0], base_year),
        (ids[1], titles[1], base_year + 1),
        (ids[2], titles[2], base_year + 2),
        (ids[3], titles[3], base_year + 3),
        (ids[4], titles[4], base_year + 4),
        (ids[5], titles[5], base_year + 2),  # isolated
        (ids[6], titles[6], base_year + 8),  # outside tested ranges
    ]
    citations = [
        (ids[1], ids[0], '2001-01-01'),
        (ids[1], ids[0], '2007-06-15'),
        (ids[1], ids[0], '2004-03-02'),
        (ids[2], ids[0], '2008-02-02'),
        (ids[2], ids[1], '2002-01-01'),
        (ids[2], ids[1], '2009-09-09'),
        (ids[3], ids[2], '2010-10-10'),
        (ids[4], ids[3], '2011-11-11'),
        (ids[0], ids[4], '2012-12-12'),
        (ids[6], ids[0], '2020-01-01'),
        (ids[2], ids[6], '2021-01-01'),
        (999999991, ids[0], '2022-01-01'),
    ]

    try:
        for suffix in ('-journal', '-wal', '-shm'):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        try:
            os.remove(DB_PATH)
        except FileNotFoundError:
            pass

        conn = sqlite3.connect(DB_PATH)
        conn.execute('CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, year INTEGER)')
        conn.execute('CREATE TABLE citations (source_id INTEGER, target_id INTEGER, citation_date TEXT)')
        conn.executemany('INSERT INTO papers VALUES (?, ?, ?)', papers)
        conn.executemany('INSERT INTO citations VALUES (?, ?, ?)', citations)
        conn.commit()
        conn.close()

        ranges = [
            (base_year, base_year + 4),
            (base_year + 1, base_year + 3),
            (base_year + 2, base_year + 2),
        ]
        for start_year, end_year in ranges:
            data = run_script(start_year, end_year)
            expected = expected_graph(papers, citations, start_year, end_year)
            assert data.get('nodes') == expected['nodes'], (
                f"Wrong nodes for dynamic range {start_year}-{end_year}: {data.get('nodes')}"
            )
            assert data.get('edges') == expected['edges'], (
                f"Wrong edges for dynamic range {start_year}-{end_year}: {data.get('edges')}"
            )
    finally:
        for suffix in ('-journal', '-wal', '-shm'):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        with open(DB_PATH, 'wb') as f:
            f.write(original_db)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
