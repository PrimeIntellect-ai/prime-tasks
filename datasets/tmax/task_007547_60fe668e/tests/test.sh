#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import subprocess
from pathlib import Path

import pytest

PROJECT = Path('/home/user/citation_processor')
SOURCE = PROJECT / 'src/main.rs'
DB_PATH = Path('/home/user/dataset.db')
JSON_PATH = Path('/home/user/subgraph_ranked.json')
TARGET = Path('/tmp/verifier-cargo-target')

CANONICAL_PAPERS = [
    (1, 'Root Paper', 2020, 'AI'),
    (2, 'Sub Paper A', 2019, 'AI'),
    (3, 'Sub Paper B', 2018, 'Systems'),
    (4, 'Deep Paper C', 2015, 'Systems'),
    (5, 'Deep Paper D', 2017, 'AI'),
    (6, 'Outside Paper 1', 2021, 'AI'),
    (7, 'Outside Paper 2', 2021, 'Systems'),
    (8, 'Outside Paper 3', 2022, 'Theory'),
]
CANONICAL_CITATIONS = [
    (1, 2), (1, 3), (2, 4), (3, 4), (3, 5),
    (6, 4), (7, 5), (8, 2), (6, 2), (7, 2),
]

EDGE_PAPERS = [
    (1, 'Cycle Root', 2024, 'AI'),
    (2, 'Cycle A', 2023, 'AI'),
    (3, 'Cycle B', 2022, 'Systems'),
    (4, 'Reachable AI', 2021, 'AI'),
    (5, 'Outside AI', 2020, 'AI'),
    (6, 'Outside Systems', 2019, 'Systems'),
    (9, 'Deep Theory', 2018, 'Theory'),
    (12, 'Isolated', 2017, 'Theory'),
]
EDGE_CITATIONS = [
    (1, 2), (2, 3), (3, 2), (3, 4), (4, 9),
    (5, 2), (5, 2), (5, 4), (6, 4), (6, 1),
    (12, 3),
]

EXPECTED_QUERY = '''
WITH RECURSIVE
  subgraph(id) AS (
    SELECT 1
    UNION
    SELECT c.target_id
    FROM subgraph s
    JOIN citations c ON s.id = c.source_id
  ),
  citation_counts AS (
    SELECT p.id, COUNT(c.target_id) as total_citations
    FROM papers p
    LEFT JOIN citations c ON p.id = c.target_id
    GROUP BY p.id
  )
SELECT
  p.id,
  p.title,
  p.domain,
  cc.total_citations,
  RANK() OVER (
    PARTITION BY p.domain
    ORDER BY cc.total_citations DESC, p.id ASC
  ) as domain_rank
FROM subgraph s
JOIN papers p ON s.id = p.id
JOIN citation_counts cc ON p.id = cc.id
ORDER BY p.id ASC
'''


def create_database(papers, citations):
    for suffix in ('', '-wal', '-shm', '-journal'):
        path = Path(str(DB_PATH) + suffix)
        if path.exists() or path.is_symlink():
            path.unlink()

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executescript('''
            CREATE TABLE papers (
                id INTEGER PRIMARY KEY,
                title TEXT,
                year INTEGER,
                domain TEXT
            );
            CREATE TABLE citations (source_id INTEGER, target_id INTEGER);
        ''')
        conn.executemany(
            'INSERT INTO papers (id, title, year, domain) VALUES (?, ?, ?, ?)',
            papers,
        )
        conn.executemany(
            'INSERT INTO citations (source_id, target_id) VALUES (?, ?)',
            citations,
        )
        conn.commit()
    finally:
        conn.close()


def expected_from_database():
    assert DB_PATH.exists(), f'Database file missing at {DB_PATH}'
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute(EXPECTED_QUERY).fetchall()
    finally:
        conn.close()
    return [
        {
            'id': row['id'],
            'title': row['title'],
            'domain': row['domain'],
            'total_citations': row['total_citations'],
            'domain_rank': row['domain_rank'],
        }
        for row in rows
    ]


def logical_database_contents():
    conn = sqlite3.connect(DB_PATH)
    try:
        papers = conn.execute(
            'SELECT id, title, year, domain FROM papers ORDER BY id'
        ).fetchall()
        citations = conn.execute(
            'SELECT source_id, target_id FROM citations ORDER BY rowid'
        ).fetchall()
        return papers, citations
    finally:
        conn.close()


def run_program():
    if JSON_PATH.exists() or JSON_PATH.is_symlink():
        JSON_PATH.unlink()

    env = os.environ.copy()
    env['CARGO_TARGET_DIR'] = str(TARGET)
    result = subprocess.run(
        ['cargo', 'run', '--offline', '--quiet', '--manifest-path',
         str(PROJECT / 'Cargo.toml')],
        cwd=PROJECT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f'Rust program failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert JSON_PATH.exists(), f'Output file not found at {JSON_PATH}'
    assert JSON_PATH.is_file(), f'Output path is not a regular file: {JSON_PATH}'


def assert_final_output(expected_data):
    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f'Output file {JSON_PATH} is not valid JSON: {exc}')

    assert isinstance(actual_data, list), 'JSON output must be an array of objects'
    assert len(actual_data) == len(expected_data), (
        f'Expected {len(expected_data)} items in JSON array, got {len(actual_data)}'
    )

    required = {'id', 'title', 'domain', 'total_citations', 'domain_rank'}
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert isinstance(actual, dict), f'Item at index {i} is not a JSON object'
        assert set(actual) == required, (
            f'Item at index {i} must have exactly the keys {sorted(required)}'
        )
        for key in required:
            assert key in actual, f"Missing key '{key}' in item at index {i}"
            assert actual[key] == expected[key], (
                f"Mismatch in '{key}' for item at index {i}. "
                f'Expected {expected[key]}, got {actual[key]}'
            )
        assert type(actual['id']) is int
        assert type(actual['total_citations']) is int
        assert type(actual['domain_rank']) is int


def test_rust_source_and_clean_compilation():
    assert SOURCE.exists(), f'Rust source file missing at {SOURCE}'
    assert SOURCE.is_file(), f'Rust source path is not a file: {SOURCE}'
    source = SOURCE.read_text(encoding='utf-8')
    upper = source.upper()

    assert 'RUSQLITE' in upper, 'main.rs must use rusqlite to access SQLite'
    assert re.search(r'WITH\s+RECURSIVE\b', upper), (
        'main.rs must contain a recursive CTE'
    )
    assert re.search(r'RANK\s*\(\s*\)\s*OVER\s*\(', upper), (
        'main.rs must use the RANK() window function'
    )
    assert re.search(r'PARTITION\s+BY', upper), (
        'The ranking query must partition rows by domain'
    )
    assert re.search(r'COUNT\s*\(', upper), (
        'The SQL query must aggregate incoming citations'
    )
    assert 'CITATIONS' in upper and 'PAPERS' in upper

    if TARGET.exists():
        shutil.rmtree(TARGET)
    env = os.environ.copy()
    env['CARGO_TARGET_DIR'] = str(TARGET)
    result = subprocess.run(
        ['cargo', 'build', '--offline', '--manifest-path',
         str(PROJECT / 'Cargo.toml')],
        cwd=PROJECT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=240,
    )
    assert result.returncode == 0, (
        f'Rust project did not compile from source\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def exercise_case(papers, citations):
    create_database(papers, citations)
    expected = expected_from_database()
    before = logical_database_contents()
    run_program()
    assert logical_database_contents() == before, 'The program modified dataset.db'
    assert_final_output(expected)


def test_pipeline_on_controlled_databases():
    # Answers are captured before execution, so changing the writable database
    # cannot change the verifier's expected result.
    exercise_case(EDGE_PAPERS, EDGE_CITATIONS)
    # Leave both the supplied database and final JSON in their required state.
    exercise_case(CANONICAL_PAPERS, CANONICAL_CITATIONS)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
