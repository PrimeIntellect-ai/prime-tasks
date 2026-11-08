#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest
import pandas as pd
import numpy as np


def test_processed_features_exists():
    path = "/home/user/processed_features.parquet"
    assert os.path.exists(path), f"Missing required file: {path}"
    assert os.path.isfile(path), f"Expected a file, but found a directory: {path}"


def test_processed_features_columns():
    path = "/home/user/processed_features.parquet"
    assert os.path.exists(path), "Parquet file not found."

    df_agent = pd.read_parquet(path)
    expected_columns = {'id', 'cleaned_sensor_val', 'feature_score'}
    actual_columns = set(df_agent.columns)

    assert actual_columns == expected_columns, (
        f"Columns in parquet file do not match expected. "
        f"Expected: {expected_columns}, Actual: {actual_columns}"
    )


def test_feature_score_mae_and_cleaned_values():
    agent_path = "/home/user/processed_features.parquet"
    raw_path = "/home/user/data/telemetry.csv"

    assert os.path.exists(agent_path), "Agent output parquet file not found."
    assert os.path.exists(raw_path), "Original telemetry CSV file not found."

    df_agent = pd.read_parquet(agent_path)
    df_raw = pd.read_csv(raw_path)

    # Require exactly one output row for every original ID.
    assert len(df_agent) == len(df_raw), (
        f"Expected exactly {len(df_raw)} output rows, got {len(df_agent)}."
    )
    assert not df_agent['id'].isna().any(), "Agent output contains missing IDs."
    assert df_agent['id'].is_unique, "Agent output IDs must be unique."
    assert set(df_agent['id'].tolist()) == set(df_raw['id'].tolist()), (
        "Agent output IDs do not exactly match the original dataset IDs."
    )

    # Compute true expected values.
    med = df_raw['sensor_val'].median()
    df_raw['cleaned'] = df_raw['sensor_val'].fillna(med)

    p01 = df_raw['cleaned'].quantile(0.01)
    p99 = df_raw['cleaned'].quantile(0.99)
    df_raw['cleaned'] = df_raw['cleaned'].clip(lower=p01, upper=p99)

    def compute_true_score(row):
        text = str(row['log_message'])
        words = text.split()
        metric = sum(len(w)**2 for w in words)
        return row['cleaned'] * metric

    df_raw['true_score'] = df_raw.apply(compute_true_score, axis=1)

    # Align and preserve the original completeness assertion.
    df_merged = pd.merge(df_raw, df_agent, on='id', how='inner', validate='one_to_one')
    assert len(df_merged) == len(df_raw), "Agent output does not contain all rows from the original dataset."

    # Verify that the submitted cleaned values are the required median-imputed,
    # percentile-clipped values, allowing only ordinary floating-point rounding.
    assert np.isfinite(df_merged['cleaned_sensor_val'].to_numpy(dtype=float)).all(), (
        "cleaned_sensor_val contains non-finite values."
    )
    np.testing.assert_allclose(
        df_merged['cleaned_sensor_val'].to_numpy(dtype=float),
        df_merged['cleaned'].to_numpy(dtype=float),
        rtol=1e-7,
        atol=1e-7,
        err_msg="cleaned_sensor_val does not match the required cleaning procedure",
    )

    mae = np.mean(np.abs(df_merged['true_score'] - df_merged['feature_score']))

    threshold = 0.01
    assert mae < threshold, (
        f"Mean Absolute Error (MAE) of feature_score is too high. "
        f"Expected < {threshold}, but got {mae:.6f}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
