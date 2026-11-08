#!/bin/bash
set -e
mkdir -p /logs/verifier

RAW=/home/user/data/raw.csv
BACKUP=/tmp/raw.csv.verifier-backup
cp "$RAW" "$BACKUP"
restore_raw() {
    cp "$BACKUP" "$RAW"
}
trap restore_raw EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest
from sklearn.model_selection import train_test_split

SCRIPT_PATH = '/home/user/train_pipeline.py'
METRICS_PATH = '/home/user/metrics.json'
RAW_PATH = '/home/user/data/raw.csv'


def get_expected_metrics():
    """Dynamically compute the expected metrics from the current raw.csv."""
    script = r"""
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
import json

df = pd.read_csv('/home/user/data/raw.csv')
X = df.drop('target', axis=1)
y = df['target']

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

imputer = SimpleImputer(strategy='mean')
X_train_imputed = imputer.fit_transform(X_train)
X_test_imputed = imputer.transform(X_test)

scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train_imputed)
X_test_scaled = scaler.transform(X_test_imputed)

model = LogisticRegression(random_state=42)
model.fit(X_train_scaled, y_train)
preds = model.predict(X_test_scaled)

expected_accuracy = accuracy_score(y_test, preds)
expected_f0_mean = float(np.mean(X_test_scaled[:, 0]))

print(json.dumps({'accuracy': expected_accuracy, 'test_feature_0_mean': expected_f0_mean}))
"""
    try:
        result = subprocess.run(
            [sys.executable, '-c', script],
            capture_output=True,
            text=True,
            check=True,
            timeout=60,
        )
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to compute expected metrics. Error: {e.stderr}")


def run_submission():
    assert os.path.isfile(SCRIPT_PATH), f"The file {SCRIPT_PATH} does not exist."
    if os.path.exists(METRICS_PATH):
        os.remove(METRICS_PATH)
    try:
        result = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('train_pipeline.py timed out.')
    assert result.returncode == 0, (
        f"train_pipeline.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(METRICS_PATH), (
        'Running train_pipeline.py did not create /home/user/metrics.json.'
    )


def load_metrics():
    with open(METRICS_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail('The file /home/user/metrics.json does not contain valid JSON.')


def assert_metrics(actual_metrics, expected_metrics):
    assert 'accuracy' in actual_metrics, "The 'accuracy' key is missing from metrics.json."
    assert 'test_feature_0_mean' in actual_metrics, (
        "The 'test_feature_0_mean' key is missing from metrics.json."
    )

    actual_accuracy = actual_metrics['accuracy']
    expected_accuracy = expected_metrics['accuracy']
    assert math.isclose(actual_accuracy, expected_accuracy, rel_tol=1e-5, abs_tol=1e-5), \
        f"Accuracy is incorrect. Expected {expected_accuracy}, got {actual_accuracy}. The data leakage bug might not be fully resolved."

    actual_f0_mean = actual_metrics['test_feature_0_mean']
    expected_f0_mean = expected_metrics['test_feature_0_mean']
    assert math.isclose(actual_f0_mean, expected_f0_mean, rel_tol=1e-5, abs_tol=1e-5), \
        f"Test feature 0 mean is incorrect. Expected {expected_f0_mean}, got {actual_f0_mean}. Ensure transformers are fitted ONLY on the training data."


@pytest.fixture(scope='session', autouse=True)
def execute_script_on_original_data():
    run_submission()


def test_metrics_file_exists():
    assert os.path.isfile('/home/user/metrics.json'), "The file /home/user/metrics.json does not exist."


def test_metrics_correctness():
    metrics_path = '/home/user/metrics.json'
    assert os.path.isfile(metrics_path), f"Metrics file missing at {metrics_path}"
    actual_metrics = load_metrics()
    expected_metrics = get_expected_metrics()
    assert_metrics(actual_metrics, expected_metrics)


@pytest.mark.parametrize('seed,shift', [(731, 7.5), (991, -6.0)])
def test_pipeline_generalizes_to_other_input_data(seed, shift):
    """Execute the submitted artifact on unseen data to reject hard-coded metrics."""
    rng = np.random.default_rng(seed)
    rows = 260
    X = rng.normal(loc=2.0, scale=6.0, size=(rows, 5))

    # Give the held-out rows a distribution shift. A scaler fitted on all rows
    # produces observably different output from one fitted only on training rows.
    _, test_indices = train_test_split(
        np.arange(rows), test_size=0.2, random_state=42
    )
    X[test_indices, 0] += shift
    X[test_indices, 2] -= shift * 0.4

    missing = rng.random(X.shape) < 0.14
    X[missing] = np.nan
    signal_X = np.nan_to_num(X, nan=2.0)
    logits = (
        0.55 * signal_X[:, 0]
        - 0.35 * signal_X[:, 1]
        + 0.18 * signal_X[:, 3]
        + rng.normal(0, 2.5, rows)
    )
    y = (logits > np.median(logits)).astype(int)

    df = pd.DataFrame(X, columns=[f'feature_{i}' for i in range(5)])
    df['target'] = y
    df.to_csv(RAW_PATH, index=False)

    expected_metrics = get_expected_metrics()
    run_submission()
    assert_metrics(load_metrics(), expected_metrics)
TEST_EOF

status=0
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || status=$?

# Restore the required project input. On success, rerun the corrected artifact so
# metrics.json is also left in the requested final state for the original data.
restore_raw
if [ "$status" -eq 0 ]; then
    if ! python3 /home/user/train_pipeline.py >/tmp/final_pipeline.stdout 2>/tmp/final_pipeline.stderr; then
        status=1
    fi
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
