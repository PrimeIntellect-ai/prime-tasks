#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import pandas as pd
import numpy as np
import pytest

def test_results_mse():
    results_path = '/home/user/results.csv'
    clean_db_path = '/tests/clean_workload.db'

    # Check if results file exists
    assert os.path.isfile(results_path), f"Results file not found at {results_path}"
    assert os.path.isfile(clean_db_path), f"Clean workload DB not found at {clean_db_path}"

    # Load agent's predictions
    try:
        pred_df = pd.read_csv(results_path)
    except Exception as e:
        pytest.fail(f"Failed to load {results_path} as a CSV: {e}")

    assert 'id' in pred_df.columns, "Results CSV must contain 'id' column"
    assert 'z' in pred_df.columns, "Results CSV must contain 'z' column"

    pred_df = pred_df[['id', 'z']].sort_values('id').reset_index(drop=True)

    # Load ground truth
    try:
        conn = sqlite3.connect(clean_db_path)
        df = pd.read_sql('SELECT id, x, y FROM data_points ORDER BY id', conn)
        conn.close()
    except Exception as e:
        pytest.fail(f"Failed to load clean database: {e}")

    # Apply math logic
    df['expected_z'] = np.where(df['x'] == df['y'], 0.0, (df['x']**3 + df['y']**3) / (df['x'] - df['y']))

    # Merge and compare
    merged = pd.merge(df, pred_df, on='id', how='left')

    missing_count = merged['z'].isnull().sum()
    assert missing_count == 0, f"Missing predictions for {missing_count} IDs."

    mse = np.mean((merged['expected_z'] - merged['z'])**2)

    assert mse < 1e-5, f"MSE {mse} is not strictly less than 1e-5."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
