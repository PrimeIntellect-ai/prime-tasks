#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import sys
import subprocess

import joblib
import numpy as np
import pandas as pd
import pytest
from sklearn.base import clone
from sklearn.linear_model import Ridge
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler


@pytest.fixture(scope="session", autouse=True)
def run_experiment():
    """Require the submitted experiment itself to produce fresh artifacts."""
    metrics_path = "/home/user/artifacts/metrics.json"
    pipeline_path = "/home/user/artifacts/pipeline.pkl"
    for path in (metrics_path, pipeline_path):
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run(
        [sys.executable, "/home/user/src/experiment.py"],
        cwd="/home/user/src",
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        "experiment.py failed to execute.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def get_expected_metrics():
    """Compute the expected bootstrap metrics independently."""
    script = """
import pandas as pd
import numpy as np
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error
from sklearn.pipeline import Pipeline
from sklearn.base import BaseEstimator, TransformerMixin

df = pd.read_csv('/home/user/data/dataset.csv')
X = df.drop('target', axis=1)
y = df['target']

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

class CorrelationSelector(BaseEstimator, TransformerMixin):
    def __init__(self, threshold=0.85):
        self.threshold = threshold
        self.drop_cols = []

    def fit(self, X, y=None):
        if isinstance(X, pd.DataFrame):
            corr = X.corr().abs()
            upper = corr.where(np.triu(np.ones(corr.shape), k=1).astype(bool))
            self.drop_cols = [column for column in upper.columns if any(upper[column] > self.threshold)]
        return self

    def transform(self, X):
        if isinstance(X, pd.DataFrame):
            return X.drop(columns=self.drop_cols)
        return X

mses = []
for i in range(100):
    X_boot = X_train.sample(frac=1.0, replace=True, random_state=i)
    y_boot = y_train.loc[X_boot.index]

    pipe = Pipeline([
        ('corr', CorrelationSelector()),
        ('scaler', StandardScaler()),
        ('ridge', Ridge())
    ])
    pipe.fit(X_boot, y_boot)
    preds = pipe.predict(X_test)
    mses.append(mean_squared_error(y_test, preds))

import json
print(json.dumps({
    "mean_mse": float(np.mean(mses)),
    "ci_lower": float(np.percentile(mses, 2.5)),
    "ci_upper": float(np.percentile(mses, 97.5))
}))
"""
    result = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True)
    if result.returncode != 0:
        pytest.fail(f"Failed to compute expected metrics. Error: {result.stderr}")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Failed to parse expected metrics JSON. Output: {result.stdout}")


def test_artifacts_exist():
    metrics_path = "/home/user/artifacts/metrics.json"
    pipeline_path = "/home/user/artifacts/pipeline.pkl"

    assert os.path.isfile(metrics_path), f"Metrics file missing at {metrics_path}"
    assert os.path.isfile(pipeline_path), f"Pipeline artifact missing at {pipeline_path}"


def test_metrics_format_and_values():
    metrics_path = "/home/user/artifacts/metrics.json"

    with open(metrics_path, "r") as f:
        try:
            student_metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {metrics_path} is not valid JSON.")

    required_keys = {"mean_mse", "ci_lower", "ci_upper"}
    assert required_keys.issubset(student_metrics.keys()), \
        f"Metrics JSON must contain keys {required_keys}. Found: {list(student_metrics.keys())}"

    expected_metrics = get_expected_metrics()

    for key in required_keys:
        student_val = student_metrics[key]
        expected_val = expected_metrics[key]

        assert isinstance(student_val, (int, float)), f"Value for {key} must be a number."

        tolerance = 0.01 * expected_val
        assert math.isclose(student_val, expected_val, abs_tol=tolerance), \
            f"Value for {key} ({student_val}) is not within 1% of expected ({expected_val}). " \
            "Check that you dropped highly correlated features (f3), fixed the data leak, and used the correct bootstrap seeds."


def _selector_output_before_scaling(pipe, X, scaler_index):
    assert scaler_index > 0, "The pipeline must select correlated features before scaling."
    selector_prefix = Pipeline(pipe.steps[:scaler_index])
    return selector_prefix.transform(X)


def test_saved_pipeline_is_fitted_and_complete():
    pipeline_path = "/home/user/artifacts/pipeline.pkl"
    try:
        pipe = joblib.load(pipeline_path)
    except Exception as exc:
        pytest.fail(f"pipeline.pkl is not a loadable joblib artifact: {exc}")

    assert isinstance(pipe, Pipeline), "pipeline.pkl must contain a sklearn Pipeline."

    scaler_indices = [i for i, (_, step) in enumerate(pipe.steps) if isinstance(step, StandardScaler)]
    ridge_indices = [i for i, (_, step) in enumerate(pipe.steps) if isinstance(step, Ridge)]
    assert scaler_indices, "The saved pipeline must contain a StandardScaler."
    assert ridge_indices, "The saved pipeline must contain a Ridge model."

    scaler_index = scaler_indices[0]
    ridge_index = ridge_indices[-1]
    assert scaler_index < ridge_index, "StandardScaler must run before Ridge."
    assert ridge_index == len(pipe.steps) - 1, "Ridge must be the final pipeline estimator."

    ridge = pipe.steps[ridge_index][1]
    assert ridge.get_params() == Ridge().get_params(), "Ridge must use default parameters."
    assert hasattr(ridge, "coef_"), "The saved Ridge model is not fitted."

    df = pd.read_csv("/home/user/data/dataset.csv")
    X = df.drop(columns="target")
    y = df["target"]
    X_train, X_test, y_train, _ = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    selected_train = _selector_output_before_scaling(pipe, X_train, scaler_index)
    selected_array = np.asarray(selected_train)
    expected_selected = X_train[["f1", "f2", "f4"]].to_numpy()
    assert selected_array.shape == expected_selected.shape, \
        "Correlation selection must drop exactly the later correlated feature f3."
    assert np.allclose(selected_array, expected_selected), \
        "Correlation selection must retain f1, f2, and f4 in column order and drop f3."

    scaler = pipe.steps[scaler_index][1]
    assert hasattr(scaler, "mean_"), "The saved StandardScaler is not fitted."
    assert np.allclose(scaler.mean_, expected_selected.mean(axis=0)), \
        "The final scaler must be fitted on the full, un-bootstrapped training set only."

    predictions = pipe.predict(X_test)
    assert predictions.shape == (len(X_test),)
    assert np.isfinite(predictions).all(), "The saved pipeline produced invalid predictions."


def test_pipeline_implements_correlation_rule_generically():
    """Refit a clone to ensure selection is correlation-based, not a fixed f3 drop."""
    pipe = joblib.load("/home/user/artifacts/pipeline.pkl")
    scaler_index = next(i for i, (_, step) in enumerate(pipe.steps) if isinstance(step, StandardScaler))

    rng = np.random.RandomState(7)
    a = rng.normal(size=120)
    b = a + rng.normal(scale=0.01, size=120)
    c = rng.normal(size=120)
    synthetic_X = pd.DataFrame({"a": a, "b": b, "c": c})
    synthetic_y = 2 * a - c + rng.normal(scale=0.1, size=120)

    refitted = clone(pipe)
    refitted.fit(synthetic_X, synthetic_y)
    selected = _selector_output_before_scaling(refitted, synthetic_X, scaler_index)
    selected_array = np.asarray(selected)
    expected = synthetic_X[["a", "c"]].to_numpy()

    assert selected_array.shape == expected.shape, \
        "For a correlated pair, the selector must drop the feature appearing later in column order."
    assert np.allclose(selected_array, expected), \
        "The selector did not apply the required Pearson-correlation column-order rule."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
