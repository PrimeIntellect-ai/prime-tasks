#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import math
import os
import random
import sqlite3
import stat
import subprocess
import sys
import tempfile

import networkx as nx
import pandas as pd


def restore_canonical_database():
    db_path = '/home/user/backup_meta.db'
    fd, tmp_path = tempfile.mkstemp(prefix='backup_meta_', suffix='.db', dir='/tmp')
    os.close(fd)
    os.unlink(tmp_path)

    random.seed(42)
    regions = ['us-east', 'us-west', 'eu-central', 'ap-south']
    conn = sqlite3.connect(tmp_path)
    cursor = conn.cursor()
    cursor.execute('CREATE TABLE nodes (node_id INTEGER PRIMARY KEY, region TEXT, is_global INTEGER)')
    for node_id in range(1, 1001):
        region = regions[random.randint(0, 3)]
        is_global = 1 if node_id % 25 == 0 else 0
        cursor.execute('INSERT INTO nodes VALUES (?, ?, ?)', (node_id, region, is_global))
    conn.commit()
    conn.close()

    os.chmod(tmp_path, 0o666)
    os.replace(tmp_path, db_path)


def test_analyze_backups():
    script_path = '/home/user/analyze_backups.py'
    assert os.path.exists(script_path), f'Script {script_path} does not exist.'
    assert stat.S_ISREG(os.lstat(script_path).st_mode), f'{script_path} is not a regular file.'

    # Restore the immutable task fixture before execution. Build the reference now,
    # so changes made by the submitted script cannot affect the expected answer.
    restore_canonical_database()

    proc = subprocess.run(
        ['/app/legacy_pathfinder', '99'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )
    edges = pd.read_csv(io.StringIO(proc.stdout))

    db_path = '/home/user/backup_meta.db'
    assert os.path.exists(db_path), f'Database {db_path} does not exist.'
    conn = sqlite3.connect(db_path)
    nodes = pd.read_sql_query('SELECT * FROM nodes', conn)
    conn.close()

    merged = edges.merge(nodes, left_on='source_node_id', right_on='node_id', suffixes=('', '_src'))
    merged = merged.merge(nodes, left_on='target_node_id', right_on='node_id', suffixes=('_src', '_tgt'))
    valid_edges = merged[
        (merged['region_src'] == merged['region_tgt']) |
        (merged['is_global_src'] == 1)
    ]

    graph = nx.from_pandas_edgelist(
        valid_edges,
        'source_node_id',
        'target_node_id',
        create_using=nx.DiGraph(),
    )
    pagerank = nx.pagerank(graph, alpha=0.85)
    sorted_reference = sorted(pagerank.items(), key=lambda item: item[1], reverse=True)[:50]
    reference_dict = dict(sorted_reference)
    reference_ids = [node_id for node_id, _ in sorted_reference]

    output_path = '/home/user/top_nodes.json'
    if os.path.lexists(output_path):
        assert not (os.path.isdir(output_path) and not os.path.islink(output_path)), \
            f'{output_path} must not be a directory.'
        os.unlink(output_path)

    result = subprocess.run(
        [sys.executable, script_path],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'{script_path} exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout[-4000:]}\n'
        f'stderr:\n{result.stderr[-4000:]}'
    )

    assert os.path.exists(output_path), f'Output file {output_path} does not exist.'
    assert stat.S_ISREG(os.lstat(output_path).st_mode), f'{output_path} is not a regular file.'

    try:
        with open(output_path, 'r', encoding='utf-8') as output_file:
            agent_data = json.load(output_file)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'File {output_path} is not valid JSON: {exc}') from exc

    assert isinstance(agent_data, list), 'JSON output must be a list of objects.'
    assert len(agent_data) == 50, f'Expected exactly 50 nodes, found {len(agent_data)}.'

    agent_dict = {}
    agent_ids = []
    for index, item in enumerate(agent_data):
        assert isinstance(item, dict), f'Item at index {index} must be an object.'
        assert 'node_id' in item, f"Item at index {index} missing 'node_id'."
        assert 'pagerank' in item, f"Item at index {index} missing 'pagerank'."
        assert set(item) == {'node_id', 'pagerank'}, f'Item at index {index} has unexpected fields.'
        assert type(item['node_id']) is int, f'node_id at index {index} must be an integer.'
        assert type(item['pagerank']) is float, f'pagerank at index {index} must be a float.'
        assert math.isfinite(item['pagerank']), f'pagerank at index {index} must be finite.'
        assert item['node_id'] not in agent_dict, f"Duplicate node_id {item['node_id']} in output."
        agent_ids.append(item['node_id'])
        agent_dict[item['node_id']] = item['pagerank']

    assert agent_ids == reference_ids, 'Output must contain the exact top 50 nodes in descending PageRank order.'

    sq_errors = []
    for node_id, ref_val in reference_dict.items():
        agent_val = agent_dict.get(node_id, 0.0)
        sq_errors.append((ref_val - agent_val) ** 2)

    rmse = math.sqrt(sum(sq_errors) / len(sq_errors))
    threshold = 0.0001
    assert rmse <= threshold, f'RMSE {rmse} is greater than the threshold {threshold}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
