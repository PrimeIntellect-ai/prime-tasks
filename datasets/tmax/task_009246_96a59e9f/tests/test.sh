#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import subprocess

import pandas as pd
import pytest
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import GridSearchCV

RESULTS_PATH = "/home/user/experiments/results.json"
BEST_PARAMS_PATH = "/home/user/experiments/best_params.json"
PIPELINE_PATH = "/home/user/scripts/pipeline.py"


@pytest.fixture(scope="session", autouse=True)
def run_submitted_pipeline():
    # Remove stale or fabricated artifacts and require the submitted script to
    # recreate both of them successfully.
    for path in (RESULTS_PATH, BEST_PARAMS_PATH):
        if os.path.exists(path):
            os.remove(path)

    completed = subprocess.run(
        ["python3", PIPELINE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert completed.returncode == 0, (
        "pipeline.py failed when executed.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULTS_PATH), "pipeline.py did not create results.json"
    assert os.path.isfile(BEST_PARAMS_PATH), "pipeline.py did not create best_params.json"


def load_pipeline_module():
    spec = importlib.util.spec_from_file_location("submitted_pipeline", PIPELINE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def independently_compute_expected():
    df1 = pd.read_csv('/home/user/data/features.csv')
    df2 = pd.read_csv('/home/user/data/categories.csv')
    df = df1.merge(df2, on='id', how='left')
    df['category_id'] = df['category_id'].fillna(-1).astype(int)

    X = df[['feature1', 'category_id']]
    y = df['target']
    search = GridSearchCV(
        RandomForestClassifier(random_state=42),
        {'n_estimators': [10, 50], 'max_depth': [3, 5]},
        cv=5,
    )
    search.fit(X, y)

    scores = {}
    for params, score in zip(search.cv_results_['params'], search.cv_results_['mean_test_score']):
        key = (int(params['n_estimators']), int(params['max_depth']))
        scores[key] = float(score)

    best = {
        'n_estimators': int(search.best_params_['n_estimators']),
        'max_depth': int(search.best_params_['max_depth']),
    }
    return df, scores, best


def test_preprocessing_behavior():
    module = load_pipeline_module()
    actual = module.load_and_prep()
    expected, _, _ = independently_compute_expected()

    assert len(actual) == len(expected), "The left join must retain every features.csv row."
    assert 'category_id' in actual.columns
    assert actual['category_id'].isna().sum() == 0, "category_id still contains missing values."
    assert pd.api.types.is_integer_dtype(actual['category_id'].dtype), (
        "category_id must be explicitly converted back to an integer dtype."
    )
    pd.testing.assert_series_equal(
        actual['id'].reset_index(drop=True),
        expected['id'].reset_index(drop=True),
        check_names=False,
    )
    pd.testing.assert_series_equal(
        actual['category_id'].reset_index(drop=True),
        expected['category_id'].reset_index(drop=True),
        check_names=False,
        check_dtype=True,
    )


def test_results_json_exists_and_format():
    results_path = RESULTS_PATH
    assert os.path.isfile(results_path), f"File {results_path} is missing."

    with open(results_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{results_path} is not a valid JSON file.")

    assert isinstance(results, list), f"{results_path} should contain a list of dictionaries."
    assert len(results) == 4, f"{results_path} should have exactly 4 entries for the grid search."

    expected_combinations = [
        {"n_estimators": 10, "max_depth": 3},
        {"n_estimators": 50, "max_depth": 3},
        {"n_estimators": 10, "max_depth": 5},
        {"n_estimators": 50, "max_depth": 5}
    ]

    found_combinations = []
    actual_scores = {}
    for entry in results:
        assert isinstance(entry, dict), "Each entry in results.json must be a dictionary."
        assert "n_estimators" in entry, "Missing 'n_estimators' in results entry."
        assert "max_depth" in entry, "Missing 'max_depth' in results entry."
        assert "mean_accuracy" in entry, "Missing 'mean_accuracy' in results entry."

        assert isinstance(entry["mean_accuracy"], float), "'mean_accuracy' must be a float."

        found_combinations.append({
            "n_estimators": entry["n_estimators"],
            "max_depth": entry["max_depth"]
        })
        key = (entry['n_estimators'], entry['max_depth'])
        assert key not in actual_scores, f"Duplicate grid search combination {key}."
        actual_scores[key] = entry['mean_accuracy']

    for combo in expected_combinations:
        assert combo in found_combinations, f"Missing grid search combination {combo} in results.json."

    _, expected_scores, _ = independently_compute_expected()
    assert set(actual_scores) == set(expected_scores)
    for key, expected_score in expected_scores.items():
        assert actual_scores[key] == pytest.approx(expected_score, rel=0, abs=1e-12), (
            f"Incorrect mean cross-validation accuracy for {key}: "
            f"got {actual_scores[key]}, expected {expected_score}."
        )


def test_best_params_json_exists_and_format():
    best_params_path = BEST_PARAMS_PATH
    assert os.path.isfile(best_params_path), f"File {best_params_path} is missing."

    with open(best_params_path, "r") as f:
        try:
            best_params = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{best_params_path} is not a valid JSON file.")

    assert isinstance(best_params, dict), f"{best_params_path} should contain a dictionary."
    assert "n_estimators" in best_params, "Missing 'n_estimators' in best_params.json."
    assert "max_depth" in best_params, "Missing 'max_depth' in best_params.json."

    assert best_params["n_estimators"] in [10, 50], "'n_estimators' should be either 10 or 50."
    assert best_params["max_depth"] in [3, 5], "'max_depth' should be either 3 or 5."

    _, _, expected_best = independently_compute_expected()
    assert best_params == expected_best, (
        f"best_params.json contains {best_params}, but the required grid search selects {expected_best}."
    )


def test_pipeline_script_modifications():
    pipeline_path = PIPELINE_PATH
    assert os.path.isfile(pipeline_path), f"Script {pipeline_path} is missing."

    with open(pipeline_path, "r") as f:
        content = f.read()

    # Preserve the original source-level assertions in addition to behavioral tests.
    assert "-1" in content, "The script does not seem to fill missing values with -1."
    assert "int" in content, "The script does not seem to cast the column to integer."
    assert "GridSearchCV" in content, "GridSearchCV is not used in the script."
    assert "42" in content, "random_state=42 does not seem to be set."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
