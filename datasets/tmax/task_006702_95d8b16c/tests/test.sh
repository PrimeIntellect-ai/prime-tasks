#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
from functools import lru_cache

import pandas as pd
import pytest
from scipy.stats import ttest_ind
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import GridSearchCV, KFold, StratifiedKFold

DATA_PATH = "/home/user/server_metrics.csv"
FEATURES = ["cpu_usage", "memory_usage", "disk_io", "temperature"]
PARAM_GRID = {
    "n_estimators": [50, 100],
    "max_depth": [None, 5, 10],
}


@lru_cache(maxsize=1)
def expected_pvalue():
    df = pd.read_csv(DATA_PATH)
    healthy = df.loc[df["failure"] == 0, "temperature"]
    failed = df.loc[df["failure"] == 1, "temperature"]
    result = ttest_ind(healthy, failed, equal_var=False)
    return f"{result.pvalue:.4f}"


@lru_cache(maxsize=1)
def accepted_grid_results():
    df = pd.read_csv(DATA_PATH)
    X = df[FEATURES]
    y = df["failure"]

    # The instruction permits ordinary unshuffled KFold. Passing cv=5 to the
    # standard sklearn classifier APIs uses unshuffled StratifiedKFold, so both
    # standard interpretations are accepted.
    splitters = [
        KFold(n_splits=5, shuffle=False),
        StratifiedKFold(n_splits=5, shuffle=False),
    ]

    results = set()
    for splitter in splitters:
        search = GridSearchCV(
            RandomForestClassifier(random_state=42),
            PARAM_GRID,
            cv=splitter,
            scoring="accuracy",
            n_jobs=1,
        )
        search.fit(X, y)
        params = search.best_params_
        results.add((params["max_depth"], params["n_estimators"], f"{search.best_score_:.4f}"))
    return results


def read_submitted_params():
    file_path = "/home/user/best_params.json"
    with open(file_path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{file_path} does not contain valid JSON.")


def test_ttest_pvalue_file():
    file_path = "/home/user/ttest_pvalue.txt"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected = expected_pvalue()
    assert content == expected, f"Expected '{expected}' in {file_path}, but found '{content}'."


def test_best_params_file():
    file_path = "/home/user/best_params.json"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    params = read_submitted_params()
    assert isinstance(params, dict), f"Expected JSON object in {file_path}."
    assert "max_depth" in params, f"'max_depth' missing from {file_path}."
    assert "n_estimators" in params, f"'n_estimators' missing from {file_path}."

    assert params["max_depth"] in [None, 5, 10], f"Invalid max_depth: {params['max_depth']}"
    assert params["n_estimators"] in [50, 100], f"Invalid n_estimators: {params['n_estimators']}"

    accepted_params = {(depth, estimators) for depth, estimators, _ in accepted_grid_results()}
    submitted = (params["max_depth"], params["n_estimators"])
    assert submitted in accepted_params, f"Parameters {params} are not the grid-search optimum."


def test_best_cv_score_file():
    file_path = "/home/user/best_cv_score.txt"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    with open(file_path, "r") as f:
        content = f.read().strip()

    try:
        score = float(content)
    except ValueError:
        pytest.fail(f"{file_path} does not contain a valid float.")

    assert 0.0 <= score <= 1.0, f"CV score {score} is out of bounds [0.0, 1.0]."

    parts = content.split(".")
    assert len(parts) == 2, f"Expected decimal point in {file_path}."
    assert len(parts[1]) == 4, f"Expected exactly 4 decimal places in {file_path}, found {len(parts[1])}."

    params = read_submitted_params()
    submitted_result = (params.get("max_depth"), params.get("n_estimators"), content)
    assert submitted_result in accepted_grid_results(), (
        f"The submitted parameters and CV score do not match a reproducible 5-fold grid search: "
        f"{submitted_result}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
