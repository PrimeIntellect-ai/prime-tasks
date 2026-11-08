#!/bin/bash
mkdir -p /logs/verifier

cat << 'RUN_EOF' > /tmp/run_pipeline_checked.py
import json
import os
import runpy
import sys

import numpy as np
import pandas as pd
from sklearn.model_selection import GridSearchCV
from sklearn.pipeline import Pipeline
from sklearn.linear_model import Ridge

DATA_PATH = "/home/user/data/metrics.csv"
OBSERVED_PATH = "/tmp/pipeline_observed.json"
df = pd.read_csv(DATA_PATH)
expected_X = df[["cpu_load", "temperature", "fan_speed"]]
expected_y = df["power_consumption"].to_numpy()
observations = []
original_fit = GridSearchCV.fit


def checked_fit(self, X, y=None, **params):
    assert isinstance(self.estimator, Pipeline), "GridSearchCV must tune a scikit-learn Pipeline."
    assert isinstance(self.estimator.steps[-1][1], Ridge), "The pipeline's final estimator must be Ridge."

    if isinstance(self.cv, int):
        folds = self.cv
    else:
        folds = self.cv.get_n_splits(X, y)
    assert folds == 5, f"GridSearchCV must use 5 folds, found {folds}."
    assert self.scoring == "neg_mean_absolute_error", \
        f"GridSearchCV scoring must be neg_mean_absolute_error, found {self.scoring!r}."

    grids = self.param_grid if isinstance(self.param_grid, list) else [self.param_grid]
    alpha_values = []
    for grid in grids:
        for key, values in grid.items():
            if key == "alpha" or key.endswith("__alpha"):
                alpha_values.extend(list(values))
    assert sorted(float(v) for v in alpha_values) == [0.1, 1.0, 10.0], \
        f"Ridge alpha grid must be [0.1, 1.0, 10.0], found {alpha_values}."

    actual_X = np.asarray(X, dtype=float)
    assert actual_X.shape == (len(expected_X), 3), \
        "GridSearchCV must be fitted from the three source feature columns."
    expected_columns = [expected_X[c].to_numpy(dtype=float) for c in expected_X.columns]
    unmatched = list(range(3))
    for col in range(3):
        matches = [j for j in unmatched if np.allclose(actual_X[:, col], expected_columns[j], equal_nan=True)]
        assert matches, "GridSearchCV received feature data that does not match metrics.csv."
        unmatched.remove(matches[0])
    assert y is not None and np.allclose(np.asarray(y, dtype=float), expected_y), \
        "GridSearchCV target does not match power_consumption in metrics.csv."

    result = original_fit(self, X, y, **params)
    best = self.best_estimator_
    assert isinstance(best, Pipeline) and isinstance(best.steps[-1][1], Ridge)
    transformed = best[:-1].transform(X)
    if hasattr(transformed, "toarray"):
        transformed = transformed.toarray()
    transformed = np.asarray(transformed, dtype=float)
    assert transformed.shape == (len(expected_X), 4), \
        f"The fitted preprocessing pipeline must produce exactly four features, found {transformed.shape}."
    assert np.isfinite(transformed).all(), \
        "The fitted feature transformer leaves NaN or infinite values before Ridge."

    alpha_key = next(k for k in self.best_params_ if k == "alpha" or k.endswith("__alpha"))
    observations.append({
        "best_alpha": float(self.best_params_[alpha_key]),
        "cv_mae": float(-self.best_score_),
    })
    return result


GridSearchCV.fit = checked_fit
try:
    try:
        runpy.run_path("/home/user/pipeline.py", run_name="__main__")
    except SystemExit as exc:
        assert exc.code in (None, 0), f"pipeline.py exited with status {exc.code}."
finally:
    GridSearchCV.fit = original_fit

assert observations, "pipeline.py did not fit a GridSearchCV instance."
with open(OBSERVED_PATH, "w") as f:
    json.dump(observations, f)
RUN_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import subprocess

import pytest

EXPECTED_FILES = [
    "/home/user/pipeline.py",
    "/home/user/test_pipeline.py",
    "/home/user/results.json",
    "/home/user/test_report.log",
]


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    # Preserve the original final-state assertion before regenerating outputs.
    for filepath in EXPECTED_FILES:
        assert os.path.exists(filepath), f"Required file is missing: {filepath}"
    assert os.path.isfile("/home/user/pipeline.py"), "pipeline.py must be a regular file."
    assert os.path.isfile("/home/user/test_pipeline.py"), "test_pipeline.py must be a regular file."

    for path in ("/home/user/results.json", "/home/user/test_report.log", "/tmp/pipeline_observed.json"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    run = subprocess.run(
        ["/home/user/venv/bin/python", "/tmp/run_pipeline_checked.py"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert run.returncode == 0, f"pipeline.py failed runtime validation:\n{run.stdout}"
    assert os.path.exists("/home/user/results.json"), "pipeline.py did not create results.json."
    assert os.path.exists("/tmp/pipeline_observed.json"), "No GridSearchCV result was observed."

    report = subprocess.run(
        ["/home/user/venv/bin/python", "-m", "pytest", "/home/user/test_pipeline.py"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    with open("/home/user/test_report.log", "w") as f:
        f.write(report.stdout)
    assert report.returncode == 0, f"The submitted pytest suite failed:\n{report.stdout}"


def test_required_files_exist():
    for filepath in EXPECTED_FILES:
        assert os.path.exists(filepath), f"Required file is missing: {filepath}"


def test_virtual_environment_exists():
    venv_python = "/home/user/venv/bin/python"
    venv_pytest = "/home/user/venv/bin/pytest"
    assert os.path.exists(venv_python), f"Virtual environment Python not found at {venv_python}"
    assert os.path.exists(venv_pytest), f"Virtual environment pytest not found at {venv_pytest}"


def test_required_test_functions_exist():
    with open("/home/user/test_pipeline.py") as f:
        tree = ast.parse(f.read())
    names = {node.name for node in ast.walk(tree) if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))}
    assert "test_mae_threshold" in names, "test_pipeline.py must define test_mae_threshold."
    assert "test_no_missing_values" in names, "test_pipeline.py must define test_no_missing_values."


def test_results_json_content():
    results_path = "/home/user/results.json"
    assert os.path.exists(results_path), f"{results_path} does not exist."
    with open(results_path) as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{results_path} does not contain valid JSON."

    expected_keys = {"best_alpha", "cv_mae", "median_fan_speed"}
    assert set(results.keys()) == expected_keys, \
        f"JSON keys must exactly match {expected_keys}, found {list(results.keys())}"
    assert isinstance(results["best_alpha"], (int, float)), "best_alpha must be a number."
    assert isinstance(results["cv_mae"], (int, float)), "cv_mae must be a number."
    assert isinstance(results["median_fan_speed"], (int, float)), "median_fan_speed must be a number."
    assert all(math.isfinite(float(results[k])) for k in expected_keys), "All result values must be finite."

    # Preserve the original assertions.
    assert abs(results["median_fan_speed"] - 3057.90) <= 1.5, \
        f"median_fan_speed {results['median_fan_speed']} is not within the expected range."
    assert 0.0 < results["cv_mae"] < 15.0, \
        f"cv_mae {results['cv_mae']} is not within the expected range (0.0 to 15.0)."

    fan_values = []
    with open("/home/user/data/metrics.csv", newline="") as f:
        for row in csv.DictReader(f):
            if row["fan_speed"] != "":
                fan_values.append(float(row["fan_speed"]))
    fan_values.sort()
    n = len(fan_values)
    actual_median = fan_values[n // 2] if n % 2 else (fan_values[n // 2 - 1] + fan_values[n // 2]) / 2
    assert math.isclose(float(results["median_fan_speed"]), actual_median, rel_tol=0, abs_tol=1e-9), \
        "median_fan_speed was not calculated from metrics.csv."

    with open("/tmp/pipeline_observed.json") as f:
        observed = json.load(f)
    assert any(
        math.isclose(float(results["best_alpha"]), item["best_alpha"], rel_tol=0, abs_tol=1e-12)
        and math.isclose(float(results["cv_mae"]), item["cv_mae"], rel_tol=1e-9, abs_tol=1e-9)
        for item in observed
    ), "results.json does not match the GridSearchCV result produced by pipeline.py."


def test_pytest_report_success():
    report_path = "/home/user/test_report.log"
    assert os.path.exists(report_path), f"{report_path} does not exist."
    with open(report_path) as f:
        content = f.read().lower()
    assert "passed" in content, "The test_report.log does not indicate that the tests passed."
    assert "test_pipeline.py" in content or "test session starts" in content, \
        "The test_report.log does not appear to be a valid pytest output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
