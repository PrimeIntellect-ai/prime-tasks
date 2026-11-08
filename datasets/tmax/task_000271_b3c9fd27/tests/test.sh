#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import struct
import pandas as pd
import numpy as np
import pytest

N = 10000
DAMPING = 0.85
ITERATIONS = 20
BACKUP_FILE = '/app/backup.dat'


def compute_expected_pagerank():
    adjacency = [[] for _ in range(N)]
    out_degree = [0] * N

    with open(BACKUP_FILE, 'rb') as f:
        while True:
            record = f.read(8)
            if not record:
                break
            assert len(record) == 8, 'backup.dat contains a truncated edge record'
            u, v = struct.unpack('ii', record)
            assert 0 <= u < N and 0 <= v < N, 'backup.dat contains an invalid node ID'
            adjacency[u].append(v)
            out_degree[u] += 1

    pr = [1.0 / N] * N
    for _ in range(ITERATIONS):
        new_pr = [0.0] * N
        dangling_sum = sum(pr[i] for i in range(N) if out_degree[i] == 0)

        for u in range(N):
            if out_degree[u] > 0:
                share = pr[u] / out_degree[u]
                for v in adjacency[u]:
                    new_pr[v] += share

        for i in range(N):
            new_pr[i] = (
                DAMPING * new_pr[i]
                + DAMPING * (dangling_sum / N)
                + (1.0 - DAMPING) / N
            )
        pr = new_pr

    return np.array([float(f'{value:.6f}') for value in pr])


def test_pagerank_csv_exists():
    agent_file = '/home/user/pagerank.csv'
    assert os.path.isfile(agent_file), f'The output file {agent_file} does not exist.'


def test_pagerank_csv_format_and_accuracy():
    agent_file = '/home/user/pagerank.csv'

    assert os.path.isfile(agent_file), f'Missing {agent_file}'
    assert os.path.isfile(BACKUP_FILE), f'Missing {BACKUP_FILE}'

    try:
        agent_df = pd.read_csv(agent_file)
    except Exception as e:
        pytest.fail(f'Failed to parse {agent_file} as CSV: {e}')

    expected_columns = ['NodeID', 'PageRank']
    assert list(agent_df.columns) == expected_columns, f'Expected columns {expected_columns}, got {list(agent_df.columns)}'

    assert agent_df['NodeID'].is_monotonic_increasing, 'The NodeID column is not sorted in ascending order.'

    expected_ids = np.arange(N)
    assert len(agent_df) == N, f'Expected {N} rows, got {len(agent_df)} rows.'
    assert np.array_equal(agent_df['NodeID'].values, expected_ids), 'NodeIDs in the output do not match the expected NodeIDs.'

    try:
        actual_pr = agent_df['PageRank'].to_numpy(dtype=float)
    except Exception as e:
        pytest.fail(f'PageRank values are not numeric: {e}')
    assert np.all(np.isfinite(actual_pr)), 'PageRank values must all be finite.'

    expected_pr = compute_expected_pagerank()

    mse = np.mean((actual_pr - expected_pr) ** 2)
    threshold = 1e-6
    assert mse < threshold, f'PageRank MSE is {mse}, which is not strictly less than the threshold {threshold}.'

    assert np.array_equal(actual_pr, expected_pr), 'PageRank values do not exactly match the required six-decimal results.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
