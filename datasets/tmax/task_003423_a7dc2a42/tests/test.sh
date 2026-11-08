#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import shutil
import sqlite3
import subprocess
import tempfile
from collections import Counter

import pytest

SCRIPT = '/home/user/analyze_network.py'
CSV_PATH = '/home/user/top_nodes.csv'
SQL_PATH = '/home/user/ranking.sql'
DB_PATH = '/home/user/network.db'


def run_script(region):
    return subprocess.run(
        ['python3', SCRIPT, region],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )


def read_csv():
    assert os.path.exists(CSV_PATH), f'File {CSV_PATH} does not exist.'
    with open(CSV_PATH, newline='') as f:
        return list(csv.reader(f))


def expected_ranked_rows(nodes, edges):
    regions = dict(nodes)
    joined = [(source, target, weight, regions[source])
              for source, target, weight in edges if source in regions]
    expected = []
    for source, target, weight, region in joined:
        rank = 1 + sum(
            1 for _, _, other_weight, other_region in joined
            if other_region == region and other_weight > weight
        )
        expected.append((source, target, weight, region, rank))
    return expected


def execute_ranking(query):
    conn = sqlite3.connect(DB_PATH)
    try:
        cur = conn.cursor()
        cur.execute(query)
        return cur.fetchall()
    except sqlite3.Error as exc:
        pytest.fail(f'Executing {SQL_PATH} failed with SQLite error: {exc}')
    finally:
        conn.close()


def test_python_script_fixed_and_executed_for_required_region():
    assert os.path.isfile(SCRIPT), f'Script file {SCRIPT} is missing or is not a file.'
    with open(SCRIPT) as f:
        content = f.read()

    # Preserve the original source-level assertions.
    assert '?' in content, "The script does not appear to use parameterized queries (missing '?')."
    assert 'JOIN' in content.upper(), 'The script does not appear to use a JOIN in the SQL query.'

    result = run_script('us-east')
    assert result.returncode == 0, (
        f'{SCRIPT} failed for us-east. stdout={result.stdout!r}, stderr={result.stderr!r}'
    )

    rows = read_csv()
    assert len(rows) == 3, f'Expected 3 rows in {CSV_PATH}, found {len(rows)}.'
    expected_rows = [
        ['n2', '0.8000'],
        ['n1', '0.2000'],
        ['n3', '0.2000'],
    ]
    assert rows == expected_rows, f'Expected CSV rows {expected_rows}, got {rows}.'


def test_ranking_sql_on_original_database():
    assert os.path.isfile(SQL_PATH), f'File {SQL_PATH} does not exist or is not a file.'
    with open(SQL_PATH) as f:
        query = f.read().strip()
    assert query, f'{SQL_PATH} is empty.'

    results = execute_ranking(query)
    assert len(results) == 8, f'Expected 8 rows from ranking query, got {len(results)}.'
    assert all(len(row) == 5 for row in results), 'Ranking query must return exactly five columns.'

    # Preserve the original selected-rank assertions.
    ranks = {(row[0], row[1]): row[4] for row in results}
    assert ranks.get(('n3', 'n2')) == 1, 'Incorrect rank for n3->n2'
    assert ranks.get(('n1', 'n2')) == 2, 'Incorrect rank for n1->n2'
    assert ranks.get(('n7', 'n8')) == 1, 'Incorrect rank for n7->n8'

    nodes = [
        ('n1', 'us-east'), ('n2', 'us-east'), ('n3', 'us-east'),
        ('n4', 'us-east'), ('n5', 'us-east'), ('n6', 'eu-west'),
        ('n7', 'eu-west'), ('n8', 'eu-west'),
    ]
    edges = [
        ('n1', 'n2', 1.5), ('n3', 'n2', 2.0), ('n4', 'n2', 0.5),
        ('n5', 'n2', 1.0), ('n2', 'n1', 1.0), ('n1', 'n3', 0.8),
        ('n6', 'n7', 1.0), ('n7', 'n8', 1.2),
    ]
    expected = expected_ranked_rows(nodes, edges)
    assert Counter(results) == Counter(expected), (
        f'Ranking query returned incorrect rows. Expected {expected}, got {results}.'
    )


def test_script_and_ranking_sql_on_generated_database():
    with open(SQL_PATH) as f:
        ranking_query = f.read().strip()

    region = "qa' OR 1=1 --"
    nodes = [
        ('a', region), ('b', region), ('c', region), ('d', region),
        ('x', 'other'), ('y', 'other'),
    ]
    edges = [
        ('a', 'x', 4.0), ('b', 'x', 3.0),
        ('c', 'a', 2.0), ('d', 'a', 2.0),
        ('a', 'b', 1.0), ('b', 'c', 1.0),
        ('x', 'c', 100.0), ('y', 'a', 50.0),
    ]

    backup = tempfile.NamedTemporaryFile(prefix='network-backup-', suffix='.db', delete=False)
    backup.close()
    shutil.copy2(DB_PATH, backup.name)

    generated_rows = None
    ranking_results = None
    result = None
    try:
        os.unlink(DB_PATH)
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute('CREATE TABLE nodes (id TEXT PRIMARY KEY, region TEXT)')
            conn.execute('CREATE TABLE edges (source TEXT, target TEXT, weight REAL)')
            conn.executemany('INSERT INTO nodes VALUES (?, ?)', nodes)
            conn.executemany('INSERT INTO edges VALUES (?, ?, ?)', edges)
            conn.commit()
        finally:
            conn.close()

        result = run_script(region)
        if result.returncode == 0 and os.path.exists(CSV_PATH):
            generated_rows = read_csv()
        ranking_results = execute_ranking(ranking_query)
    finally:
        shutil.copy2(backup.name, DB_PATH)
        os.unlink(backup.name)
        # Leave the required final artifact generated from the original fixture.
        run_script('us-east')

    assert result is not None and result.returncode == 0, (
        f'{SCRIPT} failed on a parameterization test region. '
        f'stdout={getattr(result, "stdout", "")!r}, stderr={getattr(result, "stderr", "")!r}'
    )

    # Extracted edges have source in the requested region. The resulting DiGraph
    # has five nodes; a and x tie at 2/4, then b and c tie at 1/4.
    expected_csv = [
        ['a', '0.5000'],
        ['x', '0.5000'],
        ['b', '0.2500'],
    ]
    assert generated_rows == expected_csv, (
        f'Expected generated CSV rows {expected_csv}, got {generated_rows}.'
    )

    expected_ranking = expected_ranked_rows(nodes, edges)
    assert ranking_results is not None
    assert all(len(row) == 5 for row in ranking_results), (
        'Ranking query must return source, target, weight, region, rank.'
    )
    assert Counter(ranking_results) == Counter(expected_ranking), (
        f'Ranking query failed generated-data partition/rank semantics. '
        f'Expected {expected_ranking}, got {ranking_results}.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
