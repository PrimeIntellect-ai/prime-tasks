#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest
import pandas as pd
from scipy.stats import ttest_rel
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.model_selection import GridSearchCV, cross_val_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import RobustScaler, StandardScaler


def test_best_model_json():
    """Test that best_model.json exists and has the correct structure and valid values."""
    file_path = "/home/user/best_model.json"
    assert os.path.isfile(file_path), f"Missing file: {file_path}"

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    assert "best_params" in data, "JSON missing 'best_params' key."
    assert "cv_score" in data, "JSON missing 'cv_score' key."

    best_params = data["best_params"]
    assert isinstance(best_params, dict), "'best_params' should be a dictionary."

    expected_keys = {"classifier__n_estimators", "classifier__max_depth"}
    assert expected_keys.issubset(set(best_params.keys())), f"'best_params' missing expected keys. Found: {list(best_params.keys())}"

    n_estimators = best_params["classifier__n_estimators"]
    max_depth = best_params["classifier__max_depth"]

    assert n_estimators in [50, 100], f"Invalid value for classifier__n_estimators: {n_estimators}"
    assert max_depth in [5, 10, None], f"Invalid value for classifier__max_depth: {max_depth}"

    cv_score = data["cv_score"]
    assert isinstance(cv_score, (float, int)), "'cv_score' must be a number."
    assert 0.0 <= cv_score <= 1.0, f"'cv_score' is out of expected bounds [0, 1]: {cv_score}"


def test_p_value_txt():
    """Test that p_value.txt exists and contains a valid probability value."""
    file_path = "/home/user/p_value.txt"
    assert os.path.isfile(file_path), f"Missing file: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content, f"File {file_path} is empty."

    try:
        p_value = float(content)
    except ValueError:
        pytest.fail(f"Content of {file_path} is not a valid float: {content}")

    assert 0.0 <= p_value <= 1.0, f"p-value out of bounds [0, 1]: {p_value}"

    # Check if it's rounded to 4 decimal places (allow some flexibility for trailing zeros)
    parts = content.split('.')
    if len(parts) == 2:
        assert len(parts[1]) <= 4, f"p-value should be rounded to 4 decimal places, found: {content}"


def test_outputs_match_required_computations():
    """Independently recompute the grid search and paired t-test from data.csv."""
    df = pd.read_csv("/home/user/data.csv")
    X = df.drop("target", axis=1)
    y = df["target"]

    tuning_pipeline = Pipeline([
        ("imputer", SimpleImputer(strategy="mean")),
        ("scaler", RobustScaler()),
        ("classifier", RandomForestClassifier(random_state=42)),
    ])
    param_grid = {
        "classifier__n_estimators": [50, 100],
        "classifier__max_depth": [5, 10, None],
    }
    search = GridSearchCV(tuning_pipeline, param_grid=param_grid, cv=5)
    search.fit(X, y)

    with open("/home/user/best_model.json", "r") as f:
        submitted_model = json.load(f)

    assert submitted_model["best_params"] == search.best_params_, (
        f"Incorrect best_params: expected {search.best_params_}, "
        f"found {submitted_model['best_params']}"
    )
    expected_score = round(float(search.best_score_), 4)
    assert submitted_model["cv_score"] == expected_score, (
        f"Incorrect cv_score: expected {expected_score}, "
        f"found {submitted_model['cv_score']}"
    )

    imputer = SimpleImputer(strategy="mean")
    X_imputed = imputer.fit_transform(X)
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X_imputed)
    leaky_scores = cross_val_score(
        RandomForestClassifier(n_estimators=100, random_state=42),
        X_scaled,
        y,
        cv=5,
    )

    fixed_pipeline = Pipeline([
        ("imputer", SimpleImputer(strategy="mean")),
        ("scaler", RobustScaler()),
        ("classifier", RandomForestClassifier(n_estimators=100, random_state=42)),
    ])
    fixed_scores = cross_val_score(fixed_pipeline, X, y, cv=5)
    expected_p_value = round(float(ttest_rel(leaky_scores, fixed_scores).pvalue), 4)

    with open("/home/user/p_value.txt", "r") as f:
        submitted_p_value = float(f.read().strip())
    assert submitted_p_value == expected_p_value, (
        f"Incorrect p-value: expected {expected_p_value}, found {submitted_p_value}"
    )
TEST_EOF

run_verification() {
    if [ ! -f /home/user/fixed_train.py ]; then
        echo "Missing /home/user/fixed_train.py" >&2
        return 1
    fi

    data_hash_before=$(sha256sum /home/user/data.csv | awk '{print $1}') || return 1
    rm -f /home/user/best_model.json /home/user/p_value.txt

    if ! (cd /home/user && timeout 240s python3 /home/user/fixed_train.py) >/tmp/fixed_train.out 2>/tmp/fixed_train.err; then
        cat /tmp/fixed_train.out /tmp/fixed_train.err >&2
        return 1
    fi

    if [ ! -f /home/user/fixed_train.py ]; then
        echo "/home/user/fixed_train.py was removed during execution" >&2
        return 1
    fi

    data_hash_after=$(sha256sum /home/user/data.csv | awk '{print $1}') || return 1
    if [ "$data_hash_before" != "$data_hash_after" ]; then
        echo "/home/user/data.csv was modified" >&2
        return 1
    fi

    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
}

if run_verification; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
