#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sqlite3
import pytest

OUTPUT_PATH = '/home/user/unified_graph.json'
DB_PATH = '/home/user/research_data.db'
JSONL_PATH = '/home/user/metadata.jsonl'

ORIGINAL_SUBJECTS = [
    (1, 'Alpha'),
    (2, 'Beta'),
    (3, 'Gamma'),
    (4, 'Delta'),
]
ORIGINAL_MEASUREMENTS = [
    (1, 1, '2023-01-01 10:00:00', 10.5),
    (2, 1, '2023-01-02 10:00:00', 12.0),
    (3, 2, '2023-01-01 11:00:00', 8.2),
    (4, 3, '2023-01-01 09:00:00', 15.1),
    (5, 3, '2023-01-03 09:00:00', 14.8),
]
ORIGINAL_CACHE = [
    (1, '2023-01-01 10:00:00', 10.5),
    (2, '2023-01-01 11:00:00', 8.2),
    (3, '2023-01-01 09:00:00', 15.1),
    (4, '2023-01-01 00:00:00', 99.9),
]
ORIGINAL_METADATA = [
    {'subject_id': 1, 'attributes': {'type': 'control', 'age': 30}, 'related_subjects': [2, 3]},
    {'subject_id': 2, 'attributes': {'type': 'treatment', 'age': 25}, 'related_subjects': [3]},
    {'subject_id': 3, 'attributes': {'type': 'treatment', 'age': 28}, 'related_subjects': [4, 99]},
    {'subject_id': 4, 'attributes': {'type': 'control', 'age': 40}, 'related_subjects': [1]},
]

@pytest.fixture(scope='module')
def output_data():
    assert os.path.exists(OUTPUT_PATH), f'Output file missing at {OUTPUT_PATH}'
    with open(OUTPUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f'Output file is not valid JSON: {e}')
    return data

@pytest.fixture(scope='module')
def expected_graph():
    conn = sqlite3.connect(DB_PATH)
    try:
        subjects = conn.execute(
            'SELECT id, name FROM subjects ORDER BY id ASC'
        ).fetchall()
        latest_rows = conn.execute('''
            SELECT s.id,
                   (SELECT m.value
                      FROM measurements AS m
                     WHERE m.subject_id = s.id
                     ORDER BY m.timestamp DESC, m.id DESC
                     LIMIT 1) AS latest_value
              FROM subjects AS s
             ORDER BY s.id ASC
        ''').fetchall()
    finally:
        conn.close()

    with open(JSONL_PATH, 'r') as f:
        metadata = [json.loads(line) for line in f if line.strip()]

    metadata_by_subject = {item['subject_id']: item for item in metadata}
    latest_by_subject = dict(latest_rows)
    subject_ids = {subject_id for subject_id, _ in subjects}

    nodes = []
    for subject_id, name in subjects:
        item = metadata_by_subject.get(subject_id, {})
        nodes.append({
            'id': subject_id,
            'name': name,
            'latest_value': latest_by_subject[subject_id],
            'attributes': item.get('attributes', {}),
        })

    edges = []
    for item in metadata:
        source = item['subject_id']
        if source not in subject_ids:
            continue
        for target in item.get('related_subjects', []):
            if target in subject_ids:
                edges.append({'source': source, 'target': target})
    edges.sort(key=lambda edge: (edge['source'], edge['target']))

    return {'nodes': nodes, 'edges': edges}

def test_original_files_unmodified():
    # Check DB
    assert os.path.exists(DB_PATH), 'Original database file is missing'
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('SELECT COUNT(*) FROM subjects')
    assert c.fetchone()[0] == 4, 'Subjects table was modified'
    c.execute('SELECT COUNT(*) FROM measurements')
    assert c.fetchone()[0] == 5, 'Measurements table was modified'
    conn.close()

    # Check JSONL
    assert os.path.exists(JSONL_PATH), 'Original JSONL file is missing'
    with open(JSONL_PATH, 'r') as f:
        lines = f.readlines()
    assert len(lines) == 4, 'metadata.jsonl was modified'

def test_original_contents_unmodified():
    conn = sqlite3.connect(DB_PATH)
    try:
        assert conn.execute('SELECT id, name FROM subjects ORDER BY id').fetchall() == ORIGINAL_SUBJECTS, 'Subjects table was modified'
        assert conn.execute('SELECT id, subject_id, timestamp, value FROM measurements ORDER BY id').fetchall() == ORIGINAL_MEASUREMENTS, 'Measurements table was modified'
        assert conn.execute('SELECT subject_id, latest_timestamp, value FROM latest_measurements_cache ORDER BY subject_id').fetchall() == ORIGINAL_CACHE, 'Cache table was modified'
    finally:
        conn.close()

    with open(JSONL_PATH, 'r') as f:
        metadata = [json.loads(line) for line in f if line.strip()]
    assert metadata == ORIGINAL_METADATA, 'metadata.jsonl was modified'

def test_output_schema_and_sorting(output_data):
    assert 'nodes' in output_data, "Missing 'nodes' key in output"
    assert 'edges' in output_data, "Missing 'edges' key in output"

    nodes = output_data['nodes']
    edges = output_data['edges']

    assert isinstance(nodes, list), "'nodes' must be a list"
    assert isinstance(edges, list), "'edges' must be a list"

    # Check nodes sorting
    ids = [n.get('id') for n in nodes]
    assert all(isinstance(i, int) for i in ids), 'Node IDs must be integers'
    assert ids == sorted(ids), 'Nodes are not sorted by id ascending'

    # Check edges sorting
    edge_tuples = [(e.get('source'), e.get('target')) for e in edges]
    assert all(isinstance(s, int) and isinstance(t, int) for s, t in edge_tuples), 'Edge source/target must be integers'
    assert edge_tuples == sorted(edge_tuples), 'Edges are not sorted by source then target'

def test_nodes_latest_values(output_data):
    nodes = {n['id']: n for n in output_data['nodes']}

    assert 1 in nodes
    assert nodes[1]['latest_value'] == 12.0, 'Node 1 latest_value is incorrect (did you use the stale cache?)'
    assert nodes[1]['name'] == 'Alpha'
    assert nodes[1]['attributes'] == {'type': 'control', 'age': 30}

    assert 2 in nodes
    assert nodes[2]['latest_value'] == 8.2

    assert 3 in nodes
    assert nodes[3]['latest_value'] == 14.8, 'Node 3 latest_value is incorrect (did you use the stale cache?)'

    assert 4 in nodes
    assert nodes[4]['latest_value'] is None, 'Node 4 latest_value should be null/None'

def test_edges_dangling_removed(output_data):
    edges = output_data['edges']
    edge_tuples = [(e['source'], e['target']) for e in edges]

    # 3 -> 99 should be removed because 99 is not in subjects
    assert (3, 99) not in edge_tuples, 'Dangling edge (3 -> 99) was not removed'

    # Valid edges should be present
    expected_edges = [(1, 2), (1, 3), (2, 3), (3, 4), (4, 1)]
    for edge in expected_edges:
        assert edge in edge_tuples, f'Missing expected edge {edge}'

    assert len(edge_tuples) == len(expected_edges), 'Output contains unexpected extra edges'

def test_complete_graph_matches_sources(output_data, expected_graph):
    assert set(output_data.keys()) == {'nodes', 'edges'}, 'Output contains missing or unexpected top-level keys'

    for node in output_data['nodes']:
        assert isinstance(node, dict), 'Every node must be an object'
        assert set(node.keys()) == {'id', 'name', 'latest_value', 'attributes'}, 'Node has missing or unexpected fields'
        assert type(node['id']) is int, 'Node IDs must be integers'

    for edge in output_data['edges']:
        assert isinstance(edge, dict), 'Every edge must be an object'
        assert set(edge.keys()) == {'source', 'target'}, 'Edge has missing or unexpected fields'
        assert type(edge['source']) is int and type(edge['target']) is int, 'Edge source/target must be integers'

    assert output_data == expected_graph, 'Unified graph does not exactly match the graph derived from the database and metadata'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
