#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import sqlite3
import subprocess
import uuid

import pytest

DB_PATH = '/home/user/data.db'
ETL_PATH = '/home/user/etl.py'
QUERY_PATH = '/home/user/query.py'
NODES_PATH = '/home/user/graph/nodes.jsonl'
EDGES_PATH = '/home/user/graph/edges.jsonl'
TARGET_PATH = '/home/user/target_customers.txt'


def read_jsonl(path):
    records = []
    with open(path, 'r') as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))
    return records


def canonical(records):
    return sorted(json.dumps(record, sort_keys=True, separators=(',', ':')) for record in records)


def expected_from_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        customers = [dict(r) for r in conn.execute('SELECT * FROM customers')]
        items = [dict(r) for r in conn.execute('SELECT * FROM items')]
        transactions = [dict(r) for r in conn.execute('SELECT * FROM transactions')]
        feedbacks = [dict(r) for r in conn.execute('SELECT * FROM feedbacks')]
    finally:
        conn.close()

    nodes = []
    for row in customers:
        props = {k: v for k, v in row.items() if k != 'id'}
        nodes.append({'id': 'c_' + str(row['id']), 'type': 'customer', 'properties': props})
    for row in items:
        props = {k: v for k, v in row.items() if k != 'id'}
        nodes.append({'id': 'i_' + str(row['id']), 'type': 'item', 'properties': props})

    edges = []
    for row in transactions:
        props = {k: v for k, v in row.items() if k not in ('id', 'cust_id', 'item_id')}
        edges.append({
            'src': 'c_' + str(row['cust_id']),
            'dst': 'i_' + str(row['item_id']),
            'type': 'PURCHASED',
            'properties': props,
        })
    for row in feedbacks:
        props = {k: v for k, v in row.items() if k not in ('id', 'cust_id', 'item_id')}
        edges.append({
            'src': 'c_' + str(row['cust_id']),
            'dst': 'i_' + str(row['item_id']),
            'type': 'RATED',
            'properties': props,
        })

    purchases = {(r['cust_id'], r['item_id']) for r in transactions}
    five_ratings = {(r['cust_id'], r['item_id']) for r in feedbacks if r['rating'] == 5}
    one_raters = {r['cust_id'] for r in feedbacks if r['rating'] == 1}
    matching_ids = {
        customer_id
        for customer_id, item_id in purchases
        if customer_id in one_raters
        and any(rater_id != customer_id and rated_item == item_id
                for rater_id, rated_item in five_ratings)
    }
    names = sorted(row['name'] for row in customers if row['id'] in matching_ids)
    return nodes, edges, names


def run_etl_and_query(expected_nodes, expected_edges, expected_names):
    for path in (NODES_PATH, EDGES_PATH, TARGET_PATH):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.remove(path)

    subprocess.run(['python3', ETL_PATH], cwd='/home/user', check=True, timeout=20)
    assert os.path.isfile(NODES_PATH), f'Nodes file missing at {NODES_PATH}'
    assert os.path.isfile(EDGES_PATH), f'Edges file missing at {EDGES_PATH}'
    assert canonical(read_jsonl(NODES_PATH)) == canonical(expected_nodes), \
        'ETL node output does not exactly represent the SQLite tables'
    assert canonical(read_jsonl(EDGES_PATH)) == canonical(expected_edges), \
        'ETL edge output does not exactly represent the SQLite tables'

    hidden_db = '/tmp/verifier-hidden-' + uuid.uuid4().hex + '.db'
    os.replace(DB_PATH, hidden_db)
    try:
        subprocess.run(['python3', QUERY_PATH], cwd='/home/user', check=True, timeout=20)
    finally:
        if os.path.lexists(DB_PATH):
            if os.path.isdir(DB_PATH) and not os.path.islink(DB_PATH):
                shutil.rmtree(DB_PATH)
            else:
                os.remove(DB_PATH)
        os.replace(hidden_db, DB_PATH)

    assert os.path.isfile(TARGET_PATH), f'Target output file missing at {TARGET_PATH}'
    with open(TARGET_PATH, 'r') as f:
        actual_names = [line.strip() for line in f if line.strip()]
    assert actual_names == expected_names, \
        f'Expected graph query output {expected_names!r}, got {actual_names!r}'


def test_scripts_execute_and_generate_original_pipeline():
    for path in (ETL_PATH, QUERY_PATH):
        assert os.path.isfile(path), f'Required script missing at {path}'
        assert not os.path.islink(path), f'Required script must be a real file: {path}'

    backup = '/tmp/original-data-' + uuid.uuid4().hex + '.db'
    shutil.copy2(DB_PATH, backup)
    try:
        expected_nodes, expected_edges, expected_names = expected_from_db()
        run_etl_and_query(expected_nodes, expected_edges, expected_names)
    finally:
        shutil.copy2(backup, DB_PATH)
        os.remove(backup)


def test_nodes_file():
    """Test that nodes.jsonl exists and contains the correct number and format of nodes."""
    assert os.path.isfile(NODES_PATH), f"Nodes file missing at {NODES_PATH}"

    nodes = []
    with open(NODES_PATH, 'r') as f:
        for line in f:
            if line.strip():
                nodes.append(json.loads(line))

    assert len(nodes) == 9, f"Expected 9 nodes, found {len(nodes)}"

    customers = [n for n in nodes if n.get('type') == 'customer']
    items = [n for n in nodes if n.get('type') == 'item']

    assert len(customers) == 5, f"Expected 5 customer nodes, found {len(customers)}"
    assert len(items) == 4, f"Expected 4 item nodes, found {len(items)}"

    for c in customers:
        assert c['id'].startswith('c_'), f"Customer ID {c['id']} does not start with 'c_'"
        assert 'properties' in c, "Customer node missing 'properties'"
        assert 'name' in c['properties'], "Customer properties missing 'name'"

    for i in items:
        assert i['id'].startswith('i_'), f"Item ID {i['id']} does not start with 'i_'"
        assert 'properties' in i, "Item node missing 'properties'"
        assert 'name' in i['properties'], "Item properties missing 'name'"


def test_edges_file():
    """Test that edges.jsonl exists and contains the correct number and format of edges."""
    assert os.path.isfile(EDGES_PATH), f"Edges file missing at {EDGES_PATH}"

    edges = []
    with open(EDGES_PATH, 'r') as f:
        for line in f:
            if line.strip():
                edges.append(json.loads(line))

    assert len(edges) == 11, f"Expected 11 edges (5 purchases + 6 ratings), found {len(edges)}"

    purchases = [e for e in edges if e.get('type') == 'PURCHASED']
    ratings = [e for e in edges if e.get('type') == 'RATED']

    assert len(purchases) == 5, f"Expected 5 PURCHASED edges, found {len(purchases)}"
    assert len(ratings) == 6, f"Expected 6 RATED edges, found {len(ratings)}"

    for e in edges:
        assert 'src' in e, "Edge missing 'src'"
        assert 'dst' in e, "Edge missing 'dst'"
        assert e['src'].startswith('c_'), f"Edge src {e['src']} should be a customer ID"
        assert e['dst'].startswith('i_'), f"Edge dst {e['dst']} should be an item ID"
        assert 'properties' in e, "Edge missing 'properties'"


def test_target_customers():
    """Test that target_customers.txt contains the correct output."""
    assert os.path.isfile(TARGET_PATH), f"Target output file missing at {TARGET_PATH}"

    with open(TARGET_PATH, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in target_customers.txt, found {len(lines)}"
    assert lines[0] == 'Alice', f"Expected first line to be 'Alice', got '{lines[0]}'"
    assert lines[1] == 'Diana', f"Expected second line to be 'Diana', got '{lines[1]}'"


def test_pipeline_on_changed_database():
    diana_name = 'Diana_' + uuid.uuid4().hex
    new_name = 'Customer_' + uuid.uuid4().hex
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('UPDATE feedbacks SET rating = 4 WHERE id = 1')
        conn.execute('UPDATE customers SET name = ? WHERE id = 4', (diana_name,))
        conn.execute('INSERT INTO customers VALUES (?, ?)', (6, new_name))
        conn.execute('INSERT INTO customers VALUES (?, ?)', (7, 'Reviewer_' + uuid.uuid4().hex))
        conn.execute('INSERT INTO items VALUES (?, ?, ?)', (105, 'Dynamic Item', 'Dynamic'))
        conn.execute('INSERT INTO items VALUES (?, ?, ?)', (106, 'Dynamic Low Item', 'Dynamic'))
        conn.execute('INSERT INTO transactions VALUES (?, ?, ?, ?)', (6, 6, 105, '2024-02-01'))
        conn.execute('INSERT INTO feedbacks VALUES (?, ?, ?, ?)', (7, 7, 105, 5))
        conn.execute('INSERT INTO feedbacks VALUES (?, ?, ?, ?)', (8, 6, 106, 1))
        conn.commit()
    finally:
        conn.close()

    expected_nodes, expected_edges, expected_names = expected_from_db()
    run_etl_and_query(expected_nodes, expected_edges, expected_names)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
