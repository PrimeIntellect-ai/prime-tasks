#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import runpy
from unittest.mock import patch

import pytest

RESULTS_FILE = "/home/user/research/results.json"
DATA_FILE = "/home/user/research/data.csv"
SCRIPT_FILE = "/home/user/research/train_model.py"


def get_truth_values():
    """Compute the expected values independently."""
    import subprocess

    script = """
import pandas as pd
import json
from sklearn.pipeline import Pipeline
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV, KFold

df = pd.read_csv("/home/user/research/data.csv")
X = df.drop("target", axis=1)
y = df["target"]

pipeline = Pipeline([
    ('imputer', SimpleImputer()),
    ('scaler', StandardScaler()),
    ('model', Ridge(random_state=42))
])

param_grid = {
    'imputer__strategy': ['mean', 'median'],
    'model__alpha': [0.1, 1.0, 10.0, 100.0]
}

cv = KFold(n_splits=5, shuffle=True, random_state=42)
grid_search = GridSearchCV(pipeline, param_grid, cv=cv)
grid_search.fit(X, y)

results = {
    "best_alpha": grid_search.best_params_['model__alpha'],
    "best_imputer_strategy": grid_search.best_params_['imputer__strategy'],
    "best_cv_score": round(float(grid_search.best_score_), 4)
}

print(json.dumps(results))
"""
    result = subprocess.run(
        ["python3", "-c", script],
        capture_output=True,
        text=True,
        check=True
    )
    return json.loads(result.stdout.strip())


def test_train_model_is_executed_and_uses_required_search():
    assert os.path.isfile(SCRIPT_FILE), f"The file {SCRIPT_FILE} does not exist."

    from sklearn import model_selection
    from sklearn.pipeline import Pipeline
    from sklearn.impute import SimpleImputer
    from sklearn.preprocessing import StandardScaler
    from sklearn.linear_model import Ridge
    from sklearn.model_selection import KFold, ParameterGrid

    recorded_searches = []
    real_grid_search = model_selection.GridSearchCV

    def recording_grid_search(*args, **kwargs):
        search = real_grid_search(*args, **kwargs)
        recorded_searches.append(search)
        return search

    if os.path.exists(RESULTS_FILE):
        os.remove(RESULTS_FILE)

    old_cwd = os.getcwd()
    try:
        os.chdir(os.path.dirname(SCRIPT_FILE))
        with patch.object(model_selection, "GridSearchCV", recording_grid_search):
            try:
                runpy.run_path(SCRIPT_FILE, run_name="__main__")
            except SystemExit as exc:
                assert exc.code in (None, 0), f"train_model.py exited with status {exc.code}"
    finally:
        os.chdir(old_cwd)

    assert recorded_searches, "train_model.py did not create and execute a GridSearchCV."

    matching = []
    for search in recorded_searches:
        estimator = getattr(search, "estimator", None)
        if not isinstance(estimator, Pipeline):
            continue
        if [name for name, _ in estimator.steps] != ["imputer", "scaler", "model"]:
            continue
        matching.append(search)

    assert matching, (
        "GridSearchCV must tune a Pipeline whose steps are named "
        "'imputer', 'scaler', and 'model' in that order."
    )
    search = matching[0]
    pipeline = search.estimator

    assert isinstance(pipeline.named_steps["imputer"], SimpleImputer)
    assert isinstance(pipeline.named_steps["scaler"], StandardScaler)
    assert isinstance(pipeline.named_steps["model"], Ridge)
    assert pipeline.named_steps["model"].random_state == 42

    assert isinstance(search.cv, KFold), "GridSearchCV must use a KFold object."
    assert search.cv.get_n_splits() == 5
    assert search.cv.shuffle is True
    assert search.cv.random_state == 42

    combinations = list(ParameterGrid(search.param_grid))
    expected_combinations = {
        (strategy, alpha)
        for strategy in ("mean", "median")
        for alpha in (0.1, 1.0, 10.0, 100.0)
    }
    assert len(combinations) == 8, "The parameter grid must contain exactly 8 combinations."
    assert all(
        set(params) == {"imputer__strategy", "model__alpha"}
        for params in combinations
    ), "The parameter grid must tune only imputer__strategy and model__alpha."
    actual_combinations = {
        (params["imputer__strategy"], float(params["model__alpha"]))
        for params in combinations
    }
    assert actual_combinations == expected_combinations

    assert hasattr(search, "best_params_"), "GridSearchCV was created but not fitted."
    assert hasattr(search, "best_score_"), "The fitted search has no best_score_."
    assert os.path.isfile(RESULTS_FILE), "Executing train_model.py did not create results.json."


def test_results_file_exists():
    assert os.path.isfile(RESULTS_FILE), f"The file {RESULTS_FILE} does not exist."


def test_results_content():
    assert os.path.isfile(RESULTS_FILE), f"The file {RESULTS_FILE} does not exist."

    with open(RESULTS_FILE, "r") as f:
        try:
            student_results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {RESULTS_FILE} does not contain valid JSON.")

    expected_keys = {"best_alpha", "best_imputer_strategy", "best_cv_score"}
    missing_keys = expected_keys - set(student_results.keys())
    assert not missing_keys, f"The results.json is missing keys: {missing_keys}"

    truth = get_truth_values()

    assert student_results["best_alpha"] == truth["best_alpha"], \
        f"Expected best_alpha to be {truth['best_alpha']}, got {student_results['best_alpha']}"

    assert student_results["best_imputer_strategy"] == truth["best_imputer_strategy"], \
        f"Expected best_imputer_strategy to be '{truth['best_imputer_strategy']}', got '{student_results['best_imputer_strategy']}'"

    assert isinstance(student_results["best_cv_score"], float), \
        "best_cv_score must be a float."

    assert round(student_results["best_cv_score"], 4) == truth["best_cv_score"], \
        f"Expected best_cv_score to be {truth['best_cv_score']}, got {student_results['best_cv_score']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
