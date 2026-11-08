#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import pytest

def get_ground_truth():
    """
    Computes the expected correlation and R2 score dynamically by running a script
    in a subprocess. This avoids importing third-party libraries directly in the test
    while still recomputing the truth accurately based on the exact data.
    """
    script = """
import json
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.linear_model import Ridge
from sklearn.metrics import r2_score
from sklearn.preprocessing import StandardScaler

df_meas = pd.read_csv('/home/user/data/measurements.csv')
df_targ = pd.read_csv('/home/user/data/targets.csv')

df = pd.merge(df_meas, df_targ, on='id')
df['sensor_ratio'] = df['sensor_A'] / df['sensor_B']

X = df[['sensor_A', 'sensor_B', 'sensor_C', 'sensor_ratio']]
y = df['target']

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

impute_vals = X_train.mean()
X_train_imp = X_train.fillna(impute_vals)
X_test_imp = X_test.fillna(impute_vals)

scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train_imp)
X_test_scaled = scaler.transform(X_test_imp)

corr = np.corrcoef(X_train_imp['sensor_ratio'], y_train)[0, 1]

model = Ridge(alpha=1.0)
model.fit(X_train_scaled, y_train)
preds = model.predict(X_test_scaled)
r2 = r2_score(y_test, preds)

print(json.dumps({"corr": float(corr), "r2": float(r2)}))
"""
    result = subprocess.run(['python3', '-c', script], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"Failed to compute ground truth: {result.stderr}")
    return json.loads(result.stdout)

@pytest.fixture(scope="module")
def truth():
    return get_ground_truth()

@pytest.fixture(scope="module")
def student_results():
    results_path = '/home/user/experiment_results.json'
    assert os.path.isfile(results_path), f"The file {results_path} does not exist. Did you save your results?"

    with open(results_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {results_path} is not valid JSON.")

    return data

def test_results_keys(student_results):
    """Check that the JSON file contains exactly the required keys."""
    expected_keys = {"train_ratio_correlation", "test_r2_score"}
    actual_keys = set(student_results.keys())

    missing = expected_keys - actual_keys
    extra = actual_keys - expected_keys

    assert not missing, f"Missing keys in experiment_results.json: {missing}"
    assert not extra, f"Extra keys found in experiment_results.json: {extra}"

def test_train_ratio_correlation(student_results, truth):
    """Check that the train_ratio_correlation matches the expected value (no leakage)."""
    expected_corr = truth['corr']
    actual_corr = student_results.get("train_ratio_correlation")

    assert isinstance(actual_corr, float), "train_ratio_correlation must be a float."
    assert abs(actual_corr - expected_corr) < 1e-4, (
        f"train_ratio_correlation mismatch. Expected ~{expected_corr:.4f}, got {actual_corr}. "
        "Make sure you calculate the correlation strictly on the training set after imputation."
    )

def test_test_r2_score(student_results, truth):
    """Check that the test_r2_score matches the expected value (no leakage)."""
    expected_r2 = truth['r2']
    actual_r2 = student_results.get("test_r2_score")

    assert isinstance(actual_r2, float), "test_r2_score must be a float."
    assert abs(actual_r2 - expected_r2) < 1e-4, (
        f"test_r2_score mismatch. Expected ~{expected_r2:.4f}, got {actual_r2}. "
        "Make sure you split the data before imputing/scaling, and apply training statistics to the test set."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
