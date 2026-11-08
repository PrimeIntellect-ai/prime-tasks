#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import secrets
import subprocess
from collections import defaultdict
import pytest

SCRIPT_PATH = '/home/user/extract_subgraph.sh'
OUTPUT_PATH = '/home/user/subgraph.cypher'
NODES_CSV = '/home/user/data/nodes.csv'
EDGES_CSV = '/home/user/data/edges.csv'


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_script_execution():
    # Replace the fixed fixtures with an unseen graph so a precomputed output
    # cannot pass. The following output check derives its answer from these files.
    suffix = secrets.token_hex(4).upper()
    a = f'A-{suffix}'
    b = f'B-{suffix}'
    c = f'C-{suffix}'
    d = f'D-{suffix}'
    e = f'E-{suffix}'
    z = f'Z-{suffix}'

    with open(NODES_CSV, 'w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['node_id', 'label', 'name'])
        writer.writerow([z, 'Unused', 'Disconnected Node'])
        writer.writerow([c, 'Place', 'Second Hop East'])
        writer.writerow(['U-007', 'Person', 'Dynamic Root'])
        writer.writerow([e, 'Place', 'Third Hop Excluded'])
        writer.writerow([a, 'Person', 'Incoming Neighbor'])
        writer.writerow([d, 'Device', 'Second Hop West'])
        writer.writerow([b, 'Person', 'Outgoing Neighbor'])

    with open(EDGES_CSV, 'w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['src_id', 'dst_id', 'relation', 'weight'])
        writer.writerow([c, e, 'OUTSIDE', '9.9'])
        writer.writerow([a, 'U-007', 'INCOMING', '1.1'])
        writer.writerow([z, e, 'DISCONNECTED', '8.8'])
        writer.writerow(['U-007', b, 'OUTGOING', '2.2'])
        writer.writerow([a, c, 'SECOND_HOP', '3.3'])
        writer.writerow([d, b, 'SECOND_HOP', '4.4'])
        writer.writerow([c, b, 'INTERNAL', '5.5'])

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    try:
        result = subprocess.run(
            ['bash', SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"The script {SCRIPT_PATH} did not finish within 15 seconds.")

    assert result.returncode == 0, (
        f"The script {SCRIPT_PATH} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), (
        f"Running {SCRIPT_PATH} did not create {OUTPUT_PATH}."
    )


def test_cypher_output():
    output_path = OUTPUT_PATH
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."

    # Recompute the expected subgraph based on the actual CSV files
    nodes = {}
    nodes_csv = NODES_CSV
    edges_csv = EDGES_CSV

    assert os.path.isfile(nodes_csv), f"Missing {nodes_csv}"
    assert os.path.isfile(edges_csv), f"Missing {edges_csv}"

    with open(nodes_csv, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            nodes[row['node_id']] = row

    edges = []
    adj = defaultdict(set)
    with open(edges_csv, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            edges.append(row)
            adj[row['src_id']].add(row['dst_id'])
            adj[row['dst_id']].add(row['src_id'])

    # Traversal logic
    target = 'U-007'
    hop0 = {target}

    hop1 = set()
    for n in hop0:
        hop1.update(adj[n])

    hop2 = set()
    for n in hop1:
        hop2.update(adj[n])

    valid_nodes = hop0 | hop1 | hop2

    # Filter edges
    valid_edges = [e for e in edges if e['src_id'] in valid_nodes and e['dst_id'] in valid_nodes]

    expected_lines = []

    # Format nodes
    sorted_nodes = sorted([n for n in valid_nodes if n in nodes])
    for n in sorted_nodes:
        node = nodes[n]
        expected_lines.append(f"CREATE (:{node['label']} {{id: '{node['node_id']}', name: '{node['name']}'}});")

    expected_lines.append("")

    # Format edges
    sorted_edges = sorted(valid_edges, key=lambda x: (x['src_id'], x['dst_id']))
    for e in sorted_edges:
        expected_lines.append(f"MATCH (a {{id: '{e['src_id']}'}}), (b {{id: '{e['dst_id']}'}}) CREATE (a)-[:{e['relation']} {{weight: {e['weight']}}}]->(b);")

    expected_content = "\n".join(expected_lines).strip()

    # Read the actual output
    with open(output_path, 'r') as f:
        actual_lines = f.read().strip().splitlines()

    # Strip trailing whitespaces from actual lines
    actual_content = "\n".join(line.rstrip() for line in actual_lines).strip()

    assert actual_content == expected_content, (
        f"The content of {output_path} does not match the expected Cypher format or subgraph logic.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
