#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess
import tempfile
import time

import numpy as np
import pandas as pd
import pytest
from scipy import stats


def test_selected_features_exists_and_is_correct():
    path = "/home/user/selected_features.txt"
    assert os.path.isfile(path), "/home/user/selected_features.txt is missing."

    train = pd.read_csv("/app/data/train_raw.csv").dropna()
    z_scores = np.abs(stats.zscore(train))
    train = train[(z_scores <= 3.0).all(axis=1)]

    columns = list(train.columns)
    corr = train.corr(method="pearson").abs()
    dropped = set()
    for i, lower in enumerate(columns):
        for higher in columns[i + 1:]:
            if corr.loc[lower, higher] > 0.85:
                dropped.add(higher)
    expected = [column for column in columns if column not in dropped]

    with open(path, "r") as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected, f"Selected features are incorrect. Expected {expected}, got {actual}."


def test_experiment_log_exists():
    path = "/home/user/experiment_log.json"
    assert os.path.isfile(path), "/home/user/experiment_log.json is missing."
    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/experiment_log.json is not valid JSON.")
    assert isinstance(data, dict) and data, "/home/user/experiment_log.json must contain a non-empty JSON object."


def test_predict_script_exists_and_executable():
    script_path = "/home/user/predict.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def evaluate_pipeline(input_path, output_path):
    script_path = "/home/user/predict.sh"
    if os.path.exists(output_path):
        os.remove(output_path)

    start_time = time.time()
    result = subprocess.run(
        [script_path, input_path, output_path],
        capture_output=True,
        text=True,
    )
    predict_time = time.time() - start_time

    assert result.returncode == 0, (
        f"predict.sh failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert os.path.isfile(output_path), f"predict.sh did not create {output_path}."

    df_raw = pd.read_csv(input_path)
    df_clean = df_raw.dropna()
    z_scores = np.abs(stats.zscore(df_clean))
    df_clean = df_clean[(z_scores <= 3.0).all(axis=1)]

    true_targets = (
        np.sin(df_clean["f0"])
        + 0.5 * df_clean["f2"]
        + np.log(np.abs(df_clean["f5"]) + 1.0)
    )

    df_preds = pd.read_csv(output_path)
    assert list(df_preds.columns) == ["target"], f"{output_path} must contain only a 'target' column."
    assert len(df_preds) == len(true_targets), (
        f"Expected {len(true_targets)} predictions after ETL, got {len(df_preds)}."
    )
    assert np.isfinite(df_preds["target"].to_numpy()).all(), "Predictions must all be finite."

    mse = np.mean((df_preds["target"].to_numpy() - true_targets.to_numpy()) ** 2)
    theoretical_oracle_time = len(df_raw) * 0.005
    speedup = theoretical_oracle_time / predict_time if predict_time > 0 else float("inf")

    assert mse <= 0.05, f"MSE is {mse:.4f}, which is > 0.05 threshold."
    assert speedup >= 50.0, (
        f"Speedup is {speedup:.2f}x, which is < 50.0x threshold. "
        f"(Predict time: {predict_time:.4f}s, Oracle theoretical: {theoretical_oracle_time:.4f}s)"
    )


def test_pipeline_performance_and_accuracy_on_provided_data():
    test_raw_path = "/app/data/test_raw.csv"
    assert os.path.isfile(test_raw_path), f"{test_raw_path} is missing. Setup issue."
    evaluate_pipeline(test_raw_path, "/app/data/test_preds.csv")


def test_pipeline_generalizes_to_hidden_data():
    seed = secrets.randbits(128)
    rng = np.random.default_rng(seed)
    n_samples = 1000
    values = rng.standard_normal((n_samples, 20))
    values[:, 1] = values[:, 0] * 2 + rng.normal(0, 0.1, n_samples)
    values[:, 6] = values[:, 2] * 3 + rng.normal(0, 0.1, n_samples)

    nan_rows = rng.choice(n_samples, 35, replace=False)
    values[nan_rows, 3] = np.nan
    remaining = np.setdiff1d(np.arange(n_samples), nan_rows)
    outlier_rows = rng.choice(remaining, 15, replace=False)
    values[outlier_rows, 4] = 10.0

    frame = pd.DataFrame(values, columns=[f"f{i}" for i in range(20)])
    with tempfile.TemporaryDirectory(prefix="proxy_hidden_") as tmpdir:
        input_path = os.path.join(tmpdir, "unseen_raw.csv")
        output_path = os.path.join(tmpdir, "unseen_preds.csv")
        frame.to_csv(input_path, index=False)
        evaluate_pipeline(input_path, output_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
