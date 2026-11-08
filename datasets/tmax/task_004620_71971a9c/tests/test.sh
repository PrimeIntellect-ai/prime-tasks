#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import pytest

def get_expected_results():
    """
    Computes the expected results by running the exact pipeline steps specified in the task.
    Uses subprocess to avoid third-party imports in the test file itself.
    """
    script = """
import pandas as pd
import numpy as np
import json
from sklearn.model_selection import train_test_split, GridSearchCV
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_squared_error

df = pd.read_csv('/home/user/sensor_data.csv')
X = df.drop(columns=['efficiency'])
y = df['efficiency']

# 1. Data Splitting
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# 2. Missing Value Handling
median_s1 = X_train['sensor_1'].median()
median_s2 = X_train['sensor_2'].median()

X_train = X_train.copy()
X_test = X_test.copy()

X_train['sensor_1'] = X_train['sensor_1'].fillna(median_s1)
X_train['sensor_2'] = X_train['sensor_2'].fillna(median_s2)
X_test['sensor_1'] = X_test['sensor_1'].fillna(median_s1)
X_test['sensor_2'] = X_test['sensor_2'].fillna(median_s2)

# 3. Outlier Handling
p01 = X_train['sensor_3'].quantile(0.01)
p99 = X_train['sensor_3'].quantile(0.99)

X_train['sensor_3'] = X_train['sensor_3'].clip(lower=p01, upper=p99)
X_test['sensor_3'] = X_test['sensor_3'].clip(lower=p01, upper=p99)

# 4. Model Training & Hyperparameter Tuning
rf = RandomForestRegressor(random_state=42)
param_grid = {
    'n_estimators': [50, 100, 200],
    'max_depth': [5, 10, None]
}

grid = GridSearchCV(rf, param_grid, cv=5)
grid.fit(X_train, y_train)

# 5. Evaluation & Reporting
preds = grid.predict(X_test)
rmse = float(np.sqrt(mean_squared_error(y_test, preds)))

expected_result = {
    "best_max_depth": grid.best_params_['max_depth'],
    "best_n_estimators": grid.best_params_['n_estimators'],
    "test_rmse": round(rmse, 4)
}

print(json.dumps(expected_result))
"""
    try:
        result = subprocess.run(['python3', '-c', script], capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to compute expected results. Script error: {e.stderr}")

def test_pipeline_results_exist():
    """Verify that the pipeline results JSON file exists."""
    results_path = "/home/user/pipeline_results.json"
    assert os.path.exists(results_path), f"The file {results_path} was not created."
    assert os.path.isfile(results_path), f"The path {results_path} is not a valid file."

def test_pipeline_results_content():
    """Verify the content of the pipeline results JSON file matches expected pipeline outputs."""
    results_path = "/home/user/pipeline_results.json"

    with open(results_path, 'r') as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {results_path} does not contain valid JSON.")

    expected = get_expected_results()

    # Check for required keys
    for key in ["best_max_depth", "best_n_estimators", "test_rmse"]:
        assert key in actual, f"Missing required key '{key}' in {results_path}."

    # Check values
    assert actual["best_max_depth"] == expected["best_max_depth"], (
        f"Incorrect best_max_depth. Expected {expected['best_max_depth']}, but got {actual['best_max_depth']}."
    )

    assert actual["best_n_estimators"] == expected["best_n_estimators"], (
        f"Incorrect best_n_estimators. Expected {expected['best_n_estimators']}, but got {actual['best_n_estimators']}."
    )

    assert isinstance(actual["test_rmse"], float), "test_rmse must be a float."
    assert actual["test_rmse"] == expected["test_rmse"], (
        f"Incorrect test_rmse. Expected {expected['test_rmse']}, but got {actual['test_rmse']}. "
        "Ensure you are applying the exact data splitting, imputation, clipping, and random state (42)."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
