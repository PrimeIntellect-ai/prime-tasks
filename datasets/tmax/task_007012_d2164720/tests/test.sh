#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sys
import subprocess
import pytest

def get_expected_metrics():
    """
    Computes the expected metrics by running the canonical scikit-learn/pandas pipeline
    in a subprocess. This ensures we derive the exact expected truth dynamically based
    on the actual data, rather than hardcoding opaque constants.
    """
    script = """
import pandas as pd
from sklearn.decomposition import PCA
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import GridSearchCV
import json

users = pd.read_csv('/home/user/data/users.csv')
txs = pd.read_csv('/home/user/data/transactions.csv')

df = pd.merge(txs, users, on='user_id', how='inner')
df = df.drop(columns=['user_id', 'transaction_id'])

X = df.drop(columns=['is_fraud'])
y = df['is_fraud']

X = X.fillna(X.mean())

pca = PCA(n_components=3, random_state=42)
X_pca = pca.fit_transform(X)

rf = RandomForestClassifier(random_state=42)
param_grid = {'max_depth': [3, 5, 7]}
grid = GridSearchCV(rf, param_grid, cv=3)
grid.fit(X_pca, y)

best_depth = int(grid.best_params_['max_depth'])
best_acc = round(float(grid.best_score_), 4)

print(json.dumps({"best_max_depth": best_depth, "best_cv_accuracy": best_acc}))
"""
    result = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to compute expected metrics. Error: {result.stderr}"

    try:
        return json.loads(result.stdout.strip())
    except json.JSONDecodeError:
        pytest.fail(f"Failed to parse expected metrics JSON. Output: {result.stdout}")

def test_experiment_log_exists():
    """Check if the experiment_log.json file was created."""
    log_file = "/home/user/experiment_log.json"
    assert os.path.exists(log_file), f"The file {log_file} does not exist. Did you run your pipeline?"
    assert os.path.isfile(log_file), f"{log_file} exists but is not a file."

def test_experiment_log_format_and_values():
    """Check if the experiment_log.json file contains the correct structure and values."""
    log_file = "/home/user/experiment_log.json"

    with open(log_file, "r") as f:
        try:
            student_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {log_file} does not contain valid JSON.")

    assert isinstance(student_data, dict), f"The JSON in {log_file} must be a dictionary/object."

    expected_keys = {"best_max_depth", "best_cv_accuracy"}
    actual_keys = set(student_data.keys())
    assert expected_keys.issubset(actual_keys), f"Missing keys in {log_file}. Expected keys: {expected_keys}. Found: {actual_keys}"

    # Dynamically compute the expected metrics
    expected_metrics = get_expected_metrics()

    expected_depth = expected_metrics["best_max_depth"]
    expected_accuracy = expected_metrics["best_cv_accuracy"]

    student_depth = student_data["best_max_depth"]
    student_accuracy = student_data["best_cv_accuracy"]

    assert student_depth == expected_depth, (
        f"Incorrect 'best_max_depth'. Expected {expected_depth}, but got {student_depth}."
    )

    assert isinstance(student_accuracy, float), (
        f"'best_cv_accuracy' must be a float, but got {type(student_accuracy).__name__}."
    )

    assert student_accuracy == expected_accuracy, (
        f"Incorrect 'best_cv_accuracy'. Expected {expected_accuracy}, but got {student_accuracy}. "
        "Make sure you rounded to exactly 4 decimal places."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
