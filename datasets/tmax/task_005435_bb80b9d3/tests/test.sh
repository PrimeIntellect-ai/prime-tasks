#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import shutil
import sqlite3
import subprocess
from collections import Counter

import pytest

SCRIPT_PATH = '/home/user/analyze.sh'
DB_PATH = '/home/user/graph.db'
OUTPUT_PATH = '/home/user/top_nodes.txt'

ENTITY_CSV = '''alpha_id,handle,profile_score
101,Alice,0.9
102,Bob,0.8
103,Charlie,0.7
104,Diana,0.6
105,Eve,0.5
'''

EVENTS_CSV = '''ref_hash,col_s,col_r,val
tx1,101,102,100
tx2,101,103,60
tx3,101,104,200
tx4,102,103,80
tx5,102,104,90
tx6,103,104,51
tx7,104,105,100
tx8,101,101,1000
tx9,101,102,120
tx10,105,101,10
'''


def derive_expected_edges():
    entities = {
        row['alpha_id']: row['handle']
        for row in csv.DictReader(io.StringIO(ENTITY_CSV))
    }
    return sorted({
        (entities[row['col_s']], entities[row['col_r']])
        for row in csv.DictReader(io.StringIO(EVENTS_CSV))
        if float(row['val']) > 50 and row['col_s'] != row['col_r']
    })


EXPECTED_EDGES = derive_expected_edges()


def remove_artifact(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} script is missing'

    # Ensure the tested database and report are produced by this execution.
    remove_artifact(DB_PATH)
    remove_artifact(OUTPUT_PATH)

    result = subprocess.run(
        ['bash', SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'{SCRIPT_PATH} failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def test_analyze_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} script is missing'


def test_graph_db_exists():
    assert os.path.isfile(DB_PATH), f'{DB_PATH} is missing'


def test_projected_edges_table_exists():
    assert os.path.isfile(DB_PATH), f'{DB_PATH} is missing'

    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='projected_edges';")
        result = cursor.fetchone()

    assert result is not None, "Table 'projected_edges' not found in /home/user/graph.db"


def test_projected_edges_contents():
    with sqlite3.connect(DB_PATH) as conn:
        columns = [row[1] for row in conn.execute("PRAGMA table_info('projected_edges')")]
        assert 'source_handle' in columns, "projected_edges lacks source_handle"
        assert 'target_handle' in columns, "projected_edges lacks target_handle"
        actual = conn.execute(
            'SELECT source_handle, target_handle FROM projected_edges '
            'ORDER BY source_handle, target_handle'
        ).fetchall()

    assert actual == EXPECTED_EDGES, (
        'projected_edges does not contain exactly the required filtered, '
        f'deduplicated graph. Expected {EXPECTED_EDGES}, got {actual}'
    )


def test_idx_source_exists():
    assert os.path.isfile(DB_PATH), f'{DB_PATH} is missing'

    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_source';")
        result = cursor.fetchone()
        cursor.execute("SELECT tbl_name FROM sqlite_master WHERE type='index' AND name='idx_source';")
        table_result = cursor.fetchone()
        indexed_columns = [row[2] for row in cursor.execute("PRAGMA index_info('idx_source')")]

    assert result is not None, "Index 'idx_source' not found in /home/user/graph.db"
    assert table_result == ('projected_edges',), "idx_source is not an index on projected_edges"
    assert indexed_columns == ['source_handle'], (
        f"idx_source must index source_handle; indexed columns were {indexed_columns}"
    )


def test_top_nodes_txt():
    assert os.path.isfile(OUTPUT_PATH), f'{OUTPUT_PATH} is missing'

    expected_content = """Handle: Alice, OutDegree: 3
Handle: Bob, OutDegree: 2
Handle: Charlie, OutDegree: 1"""

    with open(OUTPUT_PATH, 'r') as f:
        content = f.read().strip()

    assert content == expected_content, (
        f'Content of {OUTPUT_PATH} does not match expected output.\n'
        f'Expected:\n{expected_content}\nActual:\n{content}'
    )

    degrees = Counter(source for source, _ in EXPECTED_EDGES)
    derived_content = '\n'.join(
        f'Handle: {handle}, OutDegree: {degree}'
        for handle, degree in sorted(degrees.items(), key=lambda item: (-item[1], item[0]))[:3]
    )
    assert content == derived_content, 'top_nodes.txt was not derived from the required graph projection'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
