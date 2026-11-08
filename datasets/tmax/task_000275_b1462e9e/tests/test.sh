#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest
import pandas as pd
from sklearn.metrics import mean_squared_error


def build_truth():
    network = pd.read_csv('/app/data/network.csv')
    results = []
    for node in network['target_id'].unique():
        incident = network[(network['source_id'] == node) | (network['target_id'] == node)]
        t_max = incident['timestamp'].max()
        window = network[
            (network['target_id'] == node)
            & (network['timestamp'] >= t_max - 604800)
            & (network['timestamp'] <= t_max)
        ]
        results.append({'node_id': node, 'impact_score': window['weight'].sum()})
    return pd.DataFrame(results)


def test_results_csv_exists():
    """Check if the agent generated the results.csv file."""
    path = '/home/user/results.csv'
    assert os.path.exists(path), f'Agent did not create the expected output file: {path}'
    assert os.path.isfile(path), f'Path is not a file: {path}'


def test_results_mse():
    """Verify the Temporal Impact Scores against independently computed truth."""
    agent_file = '/home/user/results.csv'
    assert os.path.exists(agent_file), f'Missing agent file: {agent_file}'

    try:
        agent_df = pd.read_csv(agent_file)
    except Exception as e:
        pytest.fail(f"Failed to read agent's CSV file: {e}")

    truth_df = build_truth()

    assert 'node_id' in agent_df.columns, "Agent's CSV is missing the 'node_id' column."
    assert 'impact_score' in agent_df.columns, "Agent's CSV is missing the 'impact_score' column."

    agent_df = agent_df.sort_values('node_id').reset_index(drop=True)
    truth_df = truth_df.sort_values('node_id').reset_index(drop=True)

    assert len(agent_df) == len(truth_df), f'Row count mismatch. Expected {len(truth_df)} rows, got {len(agent_df)}.'

    pd.testing.assert_series_equal(
        agent_df['node_id'],
        truth_df['node_id'],
        obj='Node IDs',
        check_dtype=False
    )

    mse = mean_squared_error(truth_df['impact_score'], agent_df['impact_score'])
    threshold = 0.01
    assert mse <= threshold, f"MSE {mse:.6f} exceeds threshold {threshold}. Agent's scores are not accurate enough."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
