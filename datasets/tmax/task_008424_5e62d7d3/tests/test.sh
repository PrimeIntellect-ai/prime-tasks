#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import secrets
import subprocess

import numpy as np
import pandas as pd
import pytest
from sklearn.datasets import make_classification
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

TRAIN_PATH = '/home/user/train.py'
DATA_PATH = '/home/user/data.csv'
METRICS_PATH = '/home/user/metrics.json'
SCALED_PATH = '/home/user/X_train_fixed.csv'


def expected_results(df):
    X = df.drop('target', axis=1)
    y = df['target']
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)
    model = LogisticRegression(random_state=42)
    model.fit(X_train_scaled, y_train)
    accuracy = accuracy_score(y_test, model.predict(X_test_scaled))
    return X_train_scaled, accuracy


def execute_and_check(df):
    expected_scaled, expected_accuracy = expected_results(df)

    for path in (METRICS_PATH, SCALED_PATH):
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run(
        ['python3', TRAIN_PATH],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'train.py failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert os.path.exists(METRICS_PATH), 'train.py did not generate metrics.json'
    assert os.path.exists(SCALED_PATH), 'train.py did not generate X_train_fixed.csv'

    with open(METRICS_PATH, 'r') as f:
        metrics = json.load(f)
    assert 'accuracy' in metrics
    assert isinstance(metrics['accuracy'], (int, float))
    assert math.isclose(
        metrics['accuracy'], expected_accuracy, rel_tol=0.0, abs_tol=1e-12
    ), f"Expected generated accuracy {expected_accuracy}, got {metrics['accuracy']}"

    actual_scaled = np.loadtxt(SCALED_PATH, delimiter=',', ndmin=2)
    assert actual_scaled.shape == expected_scaled.shape, (
        f'Expected scaled-training shape {expected_scaled.shape}, '
        f'got {actual_scaled.shape}'
    )
    assert np.isfinite(actual_scaled).all(), 'Scaled training output contains non-finite values'
    np.testing.assert_allclose(actual_scaled, expected_scaled, rtol=1e-9, atol=1e-9)


def test_00_script_executes_and_computes_outputs_from_raw_split():
    assert os.path.exists(TRAIN_PATH), f'File not found: {TRAIN_PATH}'
    assert os.path.exists(DATA_PATH), f'File not found: {DATA_PATH}'

    with open(DATA_PATH, 'rb') as f:
        original_data = f.read()
    original_df = pd.read_csv(DATA_PATH)

    # First require the submitted script itself to regenerate and correctly compute
    # both requested artifacts for the real task data.
    execute_and_check(original_df)

    # Exercise the script on an unpredictable second dataset. Test-set-only shifts
    # make fitting the scaler on the complete dataset observably different from
    # fitting it only on the training partition.
    seed = secrets.randbits(32)
    X, y = make_classification(
        n_samples=317,
        n_features=20,
        n_informative=11,
        n_redundant=3,
        random_state=seed,
    )
    indices = np.arange(len(y))
    _, test_indices = train_test_split(indices, test_size=0.2, random_state=42)
    X[test_indices] += np.linspace(8.0, 28.0, X.shape[1])
    hidden_df = pd.DataFrame(X)
    hidden_df['target'] = y

    try:
        hidden_df.to_csv(DATA_PATH, index=False)
        execute_and_check(hidden_df)
    finally:
        # Leave the task's original input and freshly generated original outputs in
        # place for the original final-state assertions below.
        with open(DATA_PATH, 'wb') as f:
            f.write(original_data)
        for path in (METRICS_PATH, SCALED_PATH):
            if os.path.exists(path):
                os.remove(path)
        result = subprocess.run(
            ['python3', TRAIN_PATH],
            cwd='/home/user',
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert result.returncode == 0, (
            f'train.py failed while regenerating original outputs\n'
            f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
        )


def test_metrics_json_accuracy():
    """Verify that metrics.json contains the correct accuracy score."""
    metrics_path = '/home/user/metrics.json'
    assert os.path.exists(metrics_path), f"File not found: {metrics_path}"

    with open(metrics_path, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{metrics_path} is not a valid JSON file.")

    assert 'accuracy' in metrics, "metrics.json does not contain the key 'accuracy'."

    # Expected accuracy is 0.855
    expected_acc = 0.855
    actual_acc = metrics['accuracy']

    assert isinstance(actual_acc, (int, float)), "Accuracy must be a number."
    assert math.isclose(actual_acc, expected_acc, abs_tol=1e-3), \
        f"Expected accuracy close to {expected_acc}, but got {actual_acc}. The data leakage might not be properly fixed."


def test_x_train_fixed_csv():
    """Verify that X_train_fixed.csv exists, has correct dimensions, and is properly scaled."""
    csv_path = '/home/user/X_train_fixed.csv'
    assert os.path.exists(csv_path), f"File not found: {csv_path}"

    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) == 800, f"Expected 800 rows in {csv_path}, but got {len(rows)}."

    if len(rows) > 0:
        assert len(rows[0]) == 20, f"Expected 20 columns in {csv_path}, but got {len(rows[0])}."

        # Check that the first column has a mean close to 0 (StandardScaler property)
        try:
            col_0_values = [float(row[0]) for row in rows]
        except ValueError:
            pytest.fail("Could not parse values in the first column as floats.")

        mean_col_0 = sum(col_0_values) / len(col_0_values)
        assert abs(mean_col_0) < 1e-5, \
            f"Expected mean of the first column to be close to 0 (StandardScaler), but got {mean_col_0}."


def test_train_py_updated():
    """Verify that train.py has been modified to fix the data leakage."""
    train_path = '/home/user/train.py'
    assert os.path.exists(train_path), f"File not found: {train_path}"

    with open(train_path, 'r') as f:
        content = f.read()

    # Check that train_test_split is called before scaling
    assert "train_test_split(" in content, "train_test_split is missing in train.py"
    assert "StandardScaler" in content, "StandardScaler is missing in train.py"
    assert "X_train_fixed.csv" in content, "The script does not seem to save X_train_fixed.csv"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
