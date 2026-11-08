#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pandas as pd

def test_pipeline_cpp_exists():
    path = "/home/user/pipeline.cpp"
    assert os.path.isfile(path), f"C++ source code is missing at {path}"

def test_network_db_exists():
    path = "/home/user/network.db"
    assert os.path.isfile(path), f"SQLite database is missing at {path}"

def test_graph_export_csv_mse():
    agent_file = "/home/user/graph_export.csv"
    reference_file = "/tests/reference_graph.csv"

    assert os.path.isfile(agent_file), f"Agent output CSV is missing at {agent_file}"
    assert os.path.isfile(reference_file), f"Reference CSV is missing at {reference_file}"

    try:
        agent_df = pd.read_csv(agent_file)
    except Exception as e:
        assert False, f"Failed to read agent CSV: {e}"

    try:
        ref_df = pd.read_csv(reference_file)
    except Exception as e:
        assert False, f"Failed to read reference CSV: {e}"

    required_cols = ['source', 'target', 'avg_latency']
    for col in required_cols:
        assert col in agent_df.columns, f"Agent CSV is missing required column: '{col}'"

    # Merge on source and target
    merged = pd.merge(ref_df, agent_df, on=['source', 'target'], suffixes=('_ref', '_agent'))

    assert len(merged) > 0, "No matching (source, target) pairs found between agent output and reference graph."
    assert len(merged) == len(ref_df), "Not all expected (source, target) pairs are present in the agent output."

    # Calculate MSE
    mse = ((merged['avg_latency_ref'] - merged['avg_latency_agent']) ** 2).mean()

    threshold = 5.0
    assert mse <= threshold, f"MSE is {mse:.2f}, which is greater than the threshold of {threshold}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
