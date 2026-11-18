#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import subprocess
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error

PROJECT = Path("/home/user/ml_project")
PIPELINE = PROJECT / "pipeline.py"
DATA = PROJECT / "data.csv"
METRICS = PROJECT / "metrics.json"

RUNNER = r'''
import os
import runpy
import sys
import numpy as np

pipeline = os.path.abspath(sys.argv[1])
hit = [False]
original_eigh = np.linalg.eigh

def tracked_eigh(*args, **kwargs):
    frame = sys._getframe(1)
    while frame is not None:
        if frame.f_code.co_name == "custom_pca" and os.path.abspath(frame.f_code.co_filename) == pipeline:
            hit[0] = True
            break
        frame = frame.f_back
    return original_eigh(*args, **kwargs)

np.linalg.eigh = tracked_eigh
try:
    runpy.run_path(pipeline, run_name="__main__")
finally:
    np.linalg.eigh = original_eigh

if not hit[0]:
    raise SystemExit("pipeline did not execute numpy.linalg.eigh from custom_pca")
'''


def expected_metrics(csv_path):
    df = pd.read_csv(csv_path)
    X = df.drop(columns=["target"]).to_numpy()
    y = df["target"].to_numpy()

    # shuffle=False and test_size=0.2 on 500 rows means the first 400 rows train.
    split = int(len(X) * 0.8)
    X_train, X_test = X[:split], X[split:]
    y_train, y_test = y[:split], y[split:]

    train_mean = np.mean(X_train, axis=0)
    centered_train = X_train - train_mean
    covariance = np.cov(centered_train, rowvar=False)
    eigenvalues, eigenvectors = np.linalg.eigh(covariance)
    top = np.argsort(eigenvalues)[::-1][:3]
    components = eigenvectors[:, top]

    transformed_train = np.dot(centered_train, components)
    transformed_test = np.dot(X_test - train_mean, components)

    model = LinearRegression()
    model.fit(transformed_train, y_train)
    train_prediction = model.predict(transformed_train)
    test_prediction = model.predict(transformed_test)
    return {
        "train_mse": round(float(mean_squared_error(y_train, train_prediction)), 4),
        "test_mse": round(float(mean_squared_error(y_test, test_prediction)), 4),
    }


def run_pipeline_and_read_metrics():
    if METRICS.exists():
        METRICS.unlink()
    result = subprocess.run(
        [sys.executable, "-c", RUNNER, str(PIPELINE)],
        cwd=str(PROJECT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"pipeline.py failed or did not execute custom_pca with numpy.linalg.eigh.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert METRICS.is_file(), "Running pipeline.py did not create metrics.json."
    with METRICS.open() as f:
        return json.load(f)


def assert_matches_expected(actual, expected):
    assert set(actual) == {"train_mse", "test_mse"}, "metrics.json has an incorrect schema."
    for key in ("train_mse", "test_mse"):
        assert isinstance(actual[key], (int, float)) and not isinstance(actual[key], bool)
        assert np.isfinite(actual[key]), f"{key} must be finite."
        assert abs(float(actual[key]) - expected[key]) <= 0.0001, (
            f"{key} is incorrect: got {actual[key]}, expected {expected[key]}. "
            "PCA must be fit only on training data and its parameters reused on test data."
        )


def test_00_pipeline_executes_and_computes_correct_metrics():
    assert PIPELINE.is_file(), f"Expected pipeline script at {PIPELINE} does not exist."
    assert DATA.is_file(), f"Expected dataset at {DATA} does not exist."

    original_data = DATA.read_bytes()
    try:
        expected_original = expected_metrics(DATA)
        assert_matches_expected(run_pipeline_and_read_metrics(), expected_original)

        # Exercise the submitted pipeline on fresh data so fixed, fabricated metrics cannot pass.
        rng = np.random.default_rng()
        X_train = rng.normal(size=(400, 10)) @ rng.normal(size=(10, 10))
        X_test = rng.normal(size=(100, 10)) @ rng.normal(size=(10, 10))
        X_test += rng.normal(loc=4.0, scale=1.0, size=(1, 10))
        X = np.vstack([X_train, X_test])
        weights = rng.normal(size=10)
        y = X @ weights + rng.normal(scale=2.0, size=500)
        probe = pd.DataFrame(X, columns=[f"feat_{i}" for i in range(10)])
        probe["target"] = y
        probe.to_csv(DATA, index=False)

        expected_probe = expected_metrics(DATA)
        assert_matches_expected(run_pipeline_and_read_metrics(), expected_probe)
    finally:
        DATA.write_bytes(original_data)

    # Leave metrics.json corresponding to the real project dataset.
    assert_matches_expected(run_pipeline_and_read_metrics(), expected_metrics(DATA))


def test_metrics_json_exists_and_schema():
    """Verify metrics.json exists and has the correct schema."""
    metrics_path = "/home/user/ml_project/metrics.json"
    assert os.path.isfile(metrics_path), f"Expected metrics file at {metrics_path} does not exist."

    with open(metrics_path, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {metrics_path} is not valid JSON.")

    assert "train_mse" in metrics, "metrics.json is missing 'train_mse' key."
    assert "test_mse" in metrics, "metrics.json is missing 'test_mse' key."

    assert isinstance(metrics["train_mse"], (int, float)), "'train_mse' must be a number."
    assert isinstance(metrics["test_mse"], (int, float)), "'test_mse' must be a number."


def test_pipeline_no_leakage_ast():
    """Parse pipeline.py to ensure train_test_split is called before custom_pca."""
    pipeline_path = "/home/user/ml_project/pipeline.py"
    assert os.path.isfile(pipeline_path), f"Expected pipeline script at {pipeline_path} does not exist."

    with open(pipeline_path, "r") as f:
        source = f.read()

    try:
        tree = ast.parse(source)
    except SyntaxError as e:
        pytest.fail(f"Syntax error in {pipeline_path}: {e}")

    class CallVisitor(ast.NodeVisitor):
        def __init__(self):
            self.calls = []

        def visit_Call(self, node):
            if isinstance(node.func, ast.Name):
                self.calls.append(node.func.id)
            elif isinstance(node.func, ast.Attribute):
                self.calls.append(node.func.attr)
            self.generic_visit(node)

    visitor = CallVisitor()
    visitor.visit(tree)
    calls = visitor.calls

    assert "train_test_split" in calls, "train_test_split is not called in pipeline.py."
    assert "custom_pca" in calls, "custom_pca is not called in pipeline.py."

    split_idx = source.find("train_test_split")
    pca_idx = source.find("custom_pca", split_idx)

    lines = source.splitlines()
    split_line = -1
    pca_usage_line = -1
    for i, line in enumerate(lines):
        if "train_test_split(" in line:
            split_line = i
        if "custom_pca(" in line and "def custom_pca" not in line:
            pca_usage_line = i

    if split_line != -1 and pca_usage_line != -1:
        assert split_line < pca_usage_line, "Data leakage: custom_pca is called before train_test_split."

    split_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and ((isinstance(node.func, ast.Name) and node.func.id == "train_test_split")
             or (isinstance(node.func, ast.Attribute) and node.func.attr == "train_test_split"))
    ]
    assert split_calls
    valid_configuration = False
    for call in split_calls:
        keywords = {kw.arg: kw.value for kw in call.keywords if kw.arg is not None}
        try:
            test_size = ast.literal_eval(keywords["test_size"])
            random_state = ast.literal_eval(keywords["random_state"])
            shuffle = ast.literal_eval(keywords["shuffle"])
        except (KeyError, ValueError):
            continue
        if test_size == 0.2 and random_state == 42 and shuffle is False:
            valid_configuration = True
    assert valid_configuration, "train_test_split must use test_size=0.2, random_state=42, shuffle=False."

    assert "sklearn.decomposition" not in source, "sklearn.decomposition.PCA must not be used."


def test_metrics_values_changed_from_leaked():
    """Ensure the metrics are different from the leaked version, implying a fix."""
    metrics_path = "/home/user/ml_project/metrics.json"
    if not os.path.isfile(metrics_path):
        pytest.fail("metrics.json not found.")

    with open(metrics_path, "r") as f:
        metrics = json.load(f)

    train_mse = metrics["train_mse"]
    test_mse = metrics["test_mse"]

    assert train_mse > 0, "train_mse should be strictly positive."
    assert test_mse > 0, "test_mse should be strictly positive."
    assert test_mse > 100, f"test_mse ({test_mse}) seems suspiciously low, possible data leakage remaining."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
