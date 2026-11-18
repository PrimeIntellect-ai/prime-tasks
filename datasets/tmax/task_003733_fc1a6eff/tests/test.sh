#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pandas as pd
import numpy as np
import networkx as nx
import pytest


def test_influence_scores_mse():
    agent_file = '/home/user/influence_scores.csv'
    edges_file = '/app/edges.csv'

    assert os.path.isfile(agent_file), f"Agent's output file {agent_file} is missing."
    assert os.path.isfile(edges_file), f"Network data file {edges_file} is missing."

    try:
        agent_df = pd.read_csv(agent_file)
    except Exception as e:
        pytest.fail(f"Failed to read agent's output file as CSV: {e}")

    try:
        edges_df = pd.read_csv(edges_file)
    except Exception as e:
        pytest.fail(f"Failed to read network data as CSV: {e}")

    assert 'node' in agent_df.columns, "Agent's output must contain a 'node' column."
    assert 'score' in agent_df.columns, "Agent's output must contain a 'score' column."

    graph = nx.from_pandas_edgelist(
        edges_df,
        source='source',
        target='target',
        create_using=nx.DiGraph()
    )
    nodes = list(graph.nodes())
    scores = {node: 100.0 for node in nodes}

    for _ in range(15):
        new_scores = {node: 0.0 for node in nodes}
        for node in nodes:
            neighbors = list(graph.successors(node))
            if neighbors:
                new_scores[node] += scores[node] * 0.2
                distributed = scores[node] * 0.8 / len(neighbors)
                for neighbor in neighbors:
                    new_scores[neighbor] += distributed
            else:
                new_scores[node] += scores[node]

        for node in nodes:
            scores[node] = new_scores[node] + 5.0

    ref_df = pd.DataFrame(list(scores.items()), columns=['node', 'score'])

    agent_df['node'] = agent_df['node'].astype(str)
    ref_df['node'] = ref_df['node'].astype(str)

    merged = pd.merge(ref_df, agent_df, on='node', suffixes=('_ref', '_agent'))

    assert len(merged) == len(ref_df), (
        f"Agent's output is missing nodes. Expected {len(ref_df)}, "
        f"found {len(merged)} matching nodes."
    )

    mse = np.mean((merged['score_ref'] - merged['score_agent']) ** 2)

    threshold = 0.001
    assert mse <= threshold, (
        f"MSE is too high. Expected <= {threshold}, but got {mse:.6f}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
