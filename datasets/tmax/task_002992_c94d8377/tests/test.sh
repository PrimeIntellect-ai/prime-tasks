#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import time
import subprocess
import pandas as pd
import numpy as np
import pytest

def test_fast_etl_exists():
    agent_executable = '/home/user/fast_etl'
    assert os.path.exists(agent_executable), f"Agent executable not found at {agent_executable}"
    assert os.access(agent_executable, os.X_OK), f"Agent executable at {agent_executable} is not executable"

def test_fast_etl_performance_and_accuracy():
    agent_executable = '/home/user/fast_etl'
    legacy_executable = '/app/legacy_etl'

    # Generate hidden test data
    N = 100000 # Enough to show clear speedup
    df = pd.DataFrame({
        'timestamp': pd.date_range('2023-01-01', periods=N, freq='17S').strftime('%Y-%m-%dT%H:%M:%SZ'),
        'user_id': ['user_' + str(i % 100) for i in range(N)],
        'value': np.random.randn(N) * 10 + 50
    })

    test_data_path = '/tmp/test_data.csv'
    df.to_csv(test_data_path, index=False, header=False)

    legacy_out_path = '/tmp/legacy_out.csv'
    agent_out_path = '/tmp/agent_out.csv'

    # Run legacy
    start = time.time()
    result_legacy = subprocess.run(f"cat {test_data_path} | {legacy_executable} > {legacy_out_path}", shell=True)
    legacy_time = time.time() - start
    assert result_legacy.returncode == 0, "Legacy ETL failed to execute"

    # Run agent
    start = time.time()
    result_agent = subprocess.run(f"cat {test_data_path} | {agent_executable} > {agent_out_path}", shell=True)
    agent_time = time.time() - start
    assert result_agent.returncode == 0, "Agent ETL failed to execute"

    speedup = legacy_time / agent_time if agent_time > 0 else float('inf')

    legacy_df = pd.read_csv(legacy_out_path, names=['time', 'id', 'score'])
    agent_df = pd.read_csv(agent_out_path, names=['time', 'id', 'score'])

    assert len(legacy_df) == N, f"Legacy ETL output row count mismatch: expected {N}, got {len(legacy_df)}"
    assert len(agent_df) == N, f"Agent ETL output row count mismatch: expected {N}, got {len(agent_df)}"

    legacy_scores = pd.to_numeric(legacy_df['score'], errors='coerce').to_numpy(dtype=float)
    agent_scores = pd.to_numeric(agent_df['score'], errors='coerce').to_numpy(dtype=float)
    assert np.isfinite(legacy_scores).all(), "Legacy ETL produced a non-finite anomaly_score."
    assert np.isfinite(agent_scores).all(), "Agent ETL produced a missing or non-finite anomaly_score."

    mse = np.mean((legacy_scores - agent_scores)**2)
    time_match = (legacy_df['time'] == agent_df['time']).all()
    id_match = (legacy_df['id'] == agent_df['id']).all()

    assert time_match, "The aligned_time column does not match the legacy output exactly."
    assert id_match, "The masked_user_id column does not match the legacy output exactly."
    assert mse < 0.001, f"MSE of anomaly_score is {mse:.5f}, which is not less than the threshold of 0.001."
    assert speedup >= 5.0, f"Speedup is {speedup:.2f}x, which is not >= 5.0x (Legacy: {legacy_time:.2f}s, Agent: {agent_time:.2f}s)."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
