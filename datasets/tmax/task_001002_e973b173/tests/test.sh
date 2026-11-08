#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import subprocess
import sys
import pytest

def generate_expected_csv():
    script = """
import os
import sqlite3
import pandas as pd
import numpy as np
from sklearn.utils import resample
from sklearn.linear_model import LogisticRegression

def generate_expected():
    conn = sqlite3.connect('/home/user/mlops_data/metadata.db')
    df_meta = pd.read_sql_query("SELECT * FROM experiments", conn)
    conn.close()

    results = []
    for artifact_id in df_meta['artifact_id']:
        df = pd.read_csv(f'/home/user/mlops_data/logs/run_{artifact_id}.csv')
        rmses = []
        for i in range(200):
            sample = resample(df, replace=True, random_state=i)
            rmse = np.sqrt(np.mean((sample['y_true'] - sample['y_pred'])**2))
            rmses.append(rmse)
        rmse_mean = np.mean(rmses)
        rmse_lower = np.percentile(rmses, 2.5)
        rmse_upper = np.percentile(rmses, 97.5)
        results.append({
            'artifact_id': artifact_id,
            'rmse_mean': rmse_mean,
            'rmse_lower': rmse_lower,
            'rmse_upper': rmse_upper
        })
    df_features = pd.DataFrame(results)
    df_full = pd.merge(df_meta, df_features, on='artifact_id')

    train_df = df_full.dropna(subset=['is_anomalous'])
    test_df = df_full[df_full['is_anomalous'].isna()]

    features = ['training_time', 'rmse_mean', 'rmse_lower', 'rmse_upper']
    model = LogisticRegression(random_state=42)
    model.fit(train_df[features], train_df['is_anomalous'])

    df_full['predicted_anomalous'] = df_full['is_anomalous']
    if not test_df.empty:
        preds = model.predict(test_df[features])
        df_full.loc[df_full['is_anomalous'].isna(), 'predicted_anomalous'] = preds

    df_full['predicted_anomalous'] = df_full['predicted_anomalous'].astype(int)
    df_full['rmse_lower'] = df_full['rmse_lower'].round(4)
    df_full['rmse_upper'] = df_full['rmse_upper'].round(4)

    df_final = df_full[['artifact_id', 'rmse_lower', 'rmse_upper', 'predicted_anomalous']].sort_values('artifact_id')
    df_final.to_csv('/tmp/expected_audit_results.csv', index=False)

generate_expected()
"""
    with open('/tmp/generate_expected.py', 'w') as f:
        f.write(script)

    subprocess.run([sys.executable, '/tmp/generate_expected.py'], check=True)

def test_audit_script_exists_and_env_vars():
    audit_path = '/home/user/audit.py'
    assert os.path.isfile(audit_path), f"Script {audit_path} does not exist."

    with open(audit_path, 'r') as f:
        content = f.read()

    env_vars = [
        "OMP_NUM_THREADS",
        "OPENBLAS_NUM_THREADS",
        "MKL_NUM_THREADS",
        "VECLIB_MAXIMUM_THREADS",
        "NUMEXPR_NUM_THREADS"
    ]

    for var in env_vars:
        assert var in content, f"Environment variable {var} is not set in {audit_path}."
        assert "1" in content, f"Environment variable {var} does not seem to be set to '1'."

def test_audit_results_correctness():
    agent_csv = '/home/user/audit_results.csv'
    assert os.path.isfile(agent_csv), f"Output file {agent_csv} does not exist."

    generate_expected_csv()
    expected_csv = '/tmp/expected_audit_results.csv'

    with open(agent_csv, 'r') as f:
        agent_reader = list(csv.DictReader(f))

    with open(expected_csv, 'r') as f:
        expected_reader = list(csv.DictReader(f))

    assert len(agent_reader) == len(expected_reader), "Row count mismatch in audit_results.csv."

    for agent_row, exp_row in zip(agent_reader, expected_reader):
        assert agent_row['artifact_id'] == exp_row['artifact_id'], f"Artifact ID mismatch: {agent_row['artifact_id']} != {exp_row['artifact_id']}"

        # Check floats with rounding tolerance just in case of string formatting differences
        agent_lower = float(agent_row['rmse_lower'])
        exp_lower = float(exp_row['rmse_lower'])
        assert abs(agent_lower - exp_lower) < 1e-4, f"rmse_lower mismatch for {agent_row['artifact_id']}: {agent_lower} != {exp_lower}"

        agent_upper = float(agent_row['rmse_upper'])
        exp_upper = float(exp_row['rmse_upper'])
        assert abs(agent_upper - exp_upper) < 1e-4, f"rmse_upper mismatch for {agent_row['artifact_id']}: {agent_upper} != {exp_upper}"

        agent_pred = int(float(agent_row['predicted_anomalous']))
        exp_pred = int(float(exp_row['predicted_anomalous']))
        assert agent_pred == exp_pred, f"predicted_anomalous mismatch for {agent_row['artifact_id']}: {agent_pred} != {exp_pred}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
