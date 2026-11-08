#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import sqlite3
import subprocess
import tempfile

import networkx as nx
import pytest

OPTIMIZE_SQL_PATH = '/home/user/optimize.sql'
ANALYZE_PY_PATH = '/home/user/analyze.py'
SUSPECT_JSON_PATH = '/home/user/suspect.json'
DB_PATH = '/home/user/audit.db'


def expected_result():
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("SELECT document FROM raw_events").fetchall()
    finally:
        conn.close()

    graph = nx.DiGraph()
    for (raw_document,) in rows:
        document = json.loads(raw_document)
        payload = document.get('payload', {})
        metadata = payload.get('metadata', {})
        if metadata.get('status') != 'completed' or metadata.get('type') != 'transfer':
            continue
        routing = payload.get('routing', {})
        source = routing.get('sender_id')
        destination = routing.get('receiver_id')
        if source is not None and destination is not None:
            graph.add_edge(source, destination)

    scores = nx.pagerank(graph)
    cyclic_nodes = set()
    for component in nx.strongly_connected_components(graph):
        if len(component) > 1:
            cyclic_nodes.update(component)
        else:
            node = next(iter(component))
            if graph.has_edge(node, node):
                cyclic_nodes.add(node)

    assert cyclic_nodes, 'The test database must contain at least one directed cycle.'
    suspect = max(cyclic_nodes, key=lambda node: scores[node])
    return suspect, round(scores[suspect], 4)


def run_analysis():
    if os.path.lexists(SUSPECT_JSON_PATH):
        os.remove(SUSPECT_JSON_PATH)

    result = subprocess.run(
        ['python3', ANALYZE_PY_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f'analyze.py failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert os.path.exists(SUSPECT_JSON_PATH), 'analyze.py did not write suspect.json.'

    try:
        with open(SUSPECT_JSON_PATH, 'r') as handle:
            data = json.load(handle)
    except json.JSONDecodeError as exc:
        pytest.fail(f'{SUSPECT_JSON_PATH} does not contain valid JSON: {exc}')

    assert 'suspect_account' in data, "suspect.json missing 'suspect_account' key."
    assert 'pagerank_score' in data, "suspect.json missing 'pagerank_score' key."
    assert isinstance(data['pagerank_score'], (int, float)), 'pagerank_score must be a number.'
    return data


def test_complete_submission():
    # Preserve the original artifact and content assertions.
    assert os.path.exists(OPTIMIZE_SQL_PATH), f'{OPTIMIZE_SQL_PATH} does not exist.'
    with open(OPTIMIZE_SQL_PATH, 'r') as handle:
        optimize_sql = handle.read()
    lowered = optimize_sql.lower()
    assert 'create index' in lowered, 'optimize.sql does not contain CREATE INDEX statements.'
    assert 'payload' in lowered or 'routing' in lowered, (
        'optimize.sql does not seem to reference the correct JSON paths.'
    )

    assert os.path.exists(ANALYZE_PY_PATH), f'{ANALYZE_PY_PATH} does not exist.'
    assert os.path.isfile(ANALYZE_PY_PATH), f'{ANALYZE_PY_PATH} is not a file.'

    # Actually execute optimize.sql against a fresh database and inspect the
    # resulting raw_events indexes.
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_db = os.path.join(temp_dir, 'audit.db')
        conn = sqlite3.connect(temp_db)
        try:
            conn.execute('CREATE TABLE raw_events (document TEXT)')
            conn.execute(
                'INSERT INTO raw_events(document) VALUES (?)',
                (json.dumps({
                    'payload': {
                        'metadata': {'type': 'transfer', 'status': 'completed'},
                        'routing': {'sender_id': 'S', 'receiver_id': 'D'},
                        'financials': {'amount': 1},
                    }
                }),),
            )
            conn.executescript(optimize_sql)
            index_rows = conn.execute(
                "SELECT name, COALESCE(sql, '') FROM sqlite_master "
                "WHERE type='index' AND tbl_name='raw_events'"
            ).fetchall()
            table_sql = conn.execute(
                "SELECT sql FROM sqlite_master WHERE type='table' AND name='raw_events'"
            ).fetchone()[0]
        finally:
            conn.close()

        assert index_rows, 'optimize.sql did not create an index on raw_events.'
        indexed_schema = (table_sql + '\n' + '\n'.join(sql for _, sql in index_rows)).lower()
        assert 'sender_id' in indexed_schema, 'The created indexing schema does not cover sender_id.'
        assert 'receiver_id' in indexed_schema, 'The created indexing schema does not cover receiver_id.'

    # Execute the submitted analysis on the original database and compare it
    # with an independently computed PageRank result.
    baseline_expected = expected_result()
    baseline = run_analysis()
    assert baseline['suspect_account'] == 'ACT_C', (
        f"Expected suspect_account to be 'ACT_C', but got '{baseline['suspect_account']}'."
    )
    assert abs(baseline['pagerank_score'] - 0.2312) < 0.05, (
        f"Expected pagerank_score to be around 0.2312, but got {baseline['pagerank_score']}."
    )
    assert baseline['suspect_account'] == baseline_expected[0]
    assert baseline['pagerank_score'] == baseline_expected[1]

    # Change the database so a hardcoded ACT_C result cannot pass. The answer
    # for this case is also derived independently from the modified database.
    with tempfile.TemporaryDirectory() as temp_dir:
        backup = os.path.join(temp_dir, 'audit.db.backup')
        shutil.copy2(DB_PATH, backup)
        try:
            conn = sqlite3.connect(DB_PATH)
            try:
                def add_tx(source, destination):
                    event = {
                        'payload': {
                            'metadata': {'type': 'transfer', 'status': 'completed'},
                            'routing': {'sender_id': source, 'receiver_id': destination},
                            'financials': {'amount': 25},
                        }
                    }
                    conn.execute(
                        'INSERT INTO raw_events(document) VALUES (?)',
                        (json.dumps(event),),
                    )

                add_tx('VERIFY_RING_A', 'VERIFY_RING_Z')
                add_tx('VERIFY_RING_Z', 'VERIFY_RING_A')
                for number in range(250):
                    add_tx(f'VERIFY_FEEDER_{number}', 'VERIFY_RING_Z')
                conn.commit()
            finally:
                conn.close()

            changed_expected = expected_result()
            assert changed_expected[0] != baseline_expected[0], (
                'Verifier mutation did not produce a distinct expected suspect.'
            )
            changed = run_analysis()
            assert changed['suspect_account'] == changed_expected[0]
            assert changed['pagerank_score'] == changed_expected[1]
        finally:
            shutil.copy2(backup, DB_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
