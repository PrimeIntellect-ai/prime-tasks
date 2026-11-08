#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import stat
import subprocess

import networkx as nx
import numpy as np
import pandas as pd
import pytest


def compute_golden_scores(csv_path):
    df = pd.read_csv(csv_path)
    G = nx.Graph()
    for _, row in df.iterrows():
        G.add_edge(str(row['author_A']), str(row['author_B']), weight=float(row['collaborations']))

    pr = nx.pagerank(G, alpha=0.85, weight='collaborations')
    cc = nx.clustering(G)

    scores = {}
    for node in G.nodes():
        scores[node] = 0.75 * pr[node] + 0.25 * cc[node]
    return scores


def test_fast_ranker_output():
    script_path = '/home/user/fast_ranker.py'
    output_path = '/home/user/top_authors_page1.json'
    csv_path = '/home/user/dataset/coauthors.csv'

    assert os.path.exists(script_path), f"Script {script_path} is missing"
    assert stat.S_ISREG(os.lstat(script_path).st_mode), f"{script_path} is not a regular file"
    assert os.path.getsize(script_path) > 0, f"{script_path} is empty"

    # Derive the expected result before executing the submitted artifact so the
    # execution cannot change the input used for this comparison.
    golden_scores = compute_golden_scores(csv_path)
    sorted_golden = sorted(golden_scores.items(), key=lambda x: x[1], reverse=True)
    top_50_golden = sorted_golden[:50]
    truth_dict = {str(k): v for k, v in top_50_golden}

    # Require the submitted script itself to generate a fresh output file.
    if os.path.lexists(output_path):
        os.remove(output_path)
    completed = subprocess.run(
        ['python3', script_path],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert completed.returncode == 0, (
        f"fast_ranker.py exited with status {completed.returncode}: {completed.stderr[-2000:]}"
    )

    assert os.path.exists(output_path), f"Output file {output_path} is missing"
    assert stat.S_ISREG(os.lstat(output_path).st_mode), f"{output_path} is not a regular file"

    with open(output_path, 'r') as f:
        try:
            agent_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {output_path} is not valid JSON")

    assert isinstance(agent_data, dict), "Top-level JSON value must be an object"
    assert 'results' in agent_data, "JSON missing 'results' key"
    assert 'page' in agent_data, "JSON missing 'page' key"
    assert 'page_size' in agent_data, "JSON missing 'page_size' key"
    assert 'total_nodes' in agent_data, "JSON missing 'total_nodes' key"
    assert set(agent_data) == {'page', 'page_size', 'total_nodes', 'results'}, \
        "Top-level JSON does not strictly match the required schema"
    assert agent_data['page'] == 1, "page must be 1"
    assert agent_data['page_size'] == 50, "page_size must be 50"
    assert agent_data['total_nodes'] == len(golden_scores), "total_nodes is incorrect"
    assert isinstance(agent_data['results'], list), "results must be a list"
    assert len(agent_data['results']) == min(50, len(golden_scores)), \
        "The first page must contain exactly 50 results"

    expected_nodes = [str(node) for node, _ in top_50_golden]
    actual_nodes = []
    agent_scores = []
    truth_scores = []

    for item in agent_data['results']:
        assert isinstance(item, dict), "Each result must be an object"
        assert set(item) == {'node_id', 'score'}, \
            "Each result must strictly contain node_id and score"
        assert isinstance(item['node_id'], str), "node_id must be a string"
        assert isinstance(item['score'], (int, float)) and not isinstance(item['score'], bool), \
            "score must be numeric"
        assert math.isfinite(float(item['score'])), "score must be finite"

        node = str(item['node_id'])
        actual_nodes.append(node)
        if node in truth_dict:
            agent_scores.append(item['score'])
            truth_scores.append(truth_dict[node])
        else:
            # Preserve the original penalty for missing/incorrect nodes.
            agent_scores.append(item['score'])
            truth_scores.append(0.0)

    assert len(agent_scores) > 0, "Agent output contains no results"
    assert len(set(actual_nodes)) == len(actual_nodes), "results contains duplicate nodes"
    assert actual_nodes == expected_nodes, \
        "results must be the true top 50 authors sorted by descending score"
    assert all(float(agent_scores[i]) >= float(agent_scores[i + 1])
               for i in range(len(agent_scores) - 1)), \
        "results are not sorted by descending score"

    mse = np.mean((np.array(agent_scores, dtype=float) - np.array(truth_scores, dtype=float)) ** 2)
    assert mse <= 1e-5, f"MSE {mse} is greater than threshold 1e-5"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
