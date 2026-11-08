#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import subprocess

import joblib
import numpy as np
import pandas as pd
import pytest
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.utils.validation import check_is_fitted

BASE = "/home/user/mlops_experiment"
SCRIPT_PATH = os.path.join(BASE, "train.py")
DATA_PATH = os.path.join(BASE, "data.csv")
MODEL_PATH = os.path.join(BASE, "model.pkl")
METADATA_PATH = os.path.join(BASE, "run_metadata.json")


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


@pytest.fixture(scope="session", autouse=True)
def run_training_script():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    assert os.path.isfile(DATA_PATH), f"Dataset {DATA_PATH} is missing."

    before_hash = file_hash(DATA_PATH)
    for path in (MODEL_PATH, METADATA_PATH):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd=BASE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        "train.py failed when executed.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert file_hash(DATA_PATH) == before_hash, "The training script modified data.csv."


def canonical_result():
    df = pd.read_csv(DATA_PATH)
    X = df.drop("target", axis=1)
    y = df["target"]
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    expected = Pipeline([
        ("imputer", SimpleImputer(strategy="mean")),
        ("scaler", StandardScaler()),
        ("classifier", RandomForestClassifier(random_state=42)),
    ])
    expected.fit(X_train, y_train)
    return expected, X_test, y_test


def test_metadata_json_exists_and_valid():
    """Verify that run_metadata.json exists and contains the correct structure."""
    json_path = METADATA_PATH
    assert os.path.isfile(json_path), f"Metadata file {json_path} is missing."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    assert "test_accuracy" in data, "Key 'test_accuracy' missing from metadata JSON."
    assert isinstance(data["test_accuracy"], float), "Value for 'test_accuracy' must be a float."
    assert "model_path" in data, "Key 'model_path' missing from metadata JSON."
    assert data["model_path"] == MODEL_PATH, "Value for 'model_path' is incorrect."
    assert set(data) == {"test_accuracy", "model_path"}, "Metadata JSON has an incorrect structure."

    expected, X_test, y_test = canonical_result()
    expected_accuracy = float(expected.score(X_test, y_test))
    assert data["test_accuracy"] == pytest.approx(expected_accuracy, abs=1e-12), (
        "Metadata test_accuracy does not match the required leak-free evaluation."
    )


def test_model_pkl_exists():
    """Verify that the model.pkl file was generated."""
    model_path = MODEL_PATH
    assert os.path.isfile(model_path), f"Model file {model_path} is missing."
    assert os.path.getsize(model_path) > 0, f"Model file {model_path} is empty."


def test_saved_model_is_required_fitted_pipeline():
    model = joblib.load(MODEL_PATH)
    assert isinstance(model, Pipeline), "model.pkl must contain a scikit-learn Pipeline."
    assert len(model.steps) == 3, "The saved Pipeline must contain exactly three steps."

    imputer, scaler, classifier = [step for _, step in model.steps]
    assert isinstance(imputer, SimpleImputer), "The first Pipeline step must be SimpleImputer."
    assert imputer.strategy == "mean", "SimpleImputer must use strategy='mean'."
    assert isinstance(scaler, StandardScaler), "The second Pipeline step must be StandardScaler."
    assert isinstance(classifier, RandomForestClassifier), (
        "The final Pipeline step must be RandomForestClassifier."
    )
    assert classifier.random_state == 42, "RandomForestClassifier must use random_state=42."
    check_is_fitted(model)
    check_is_fitted(imputer)
    check_is_fitted(scaler)
    check_is_fitted(classifier)

    expected, X_test, y_test = canonical_result()
    expected_imputer, expected_scaler, expected_classifier = [
        step for _, step in expected.steps
    ]

    assert imputer.get_params(deep=False) == expected_imputer.get_params(deep=False)
    assert scaler.get_params(deep=False) == expected_scaler.get_params(deep=False)
    assert classifier.get_params(deep=False) == expected_classifier.get_params(deep=False)

    np.testing.assert_allclose(imputer.statistics_, expected_imputer.statistics_, rtol=0, atol=1e-12)
    np.testing.assert_allclose(scaler.mean_, expected_scaler.mean_, rtol=0, atol=1e-12)
    np.testing.assert_allclose(scaler.var_, expected_scaler.var_, rtol=0, atol=1e-12)
    np.testing.assert_allclose(scaler.scale_, expected_scaler.scale_, rtol=0, atol=1e-12)
    np.testing.assert_array_equal(model.predict(X_test), expected.predict(X_test))
    np.testing.assert_allclose(model.predict_proba(X_test), expected.predict_proba(X_test), rtol=0, atol=1e-15)
    assert float(model.score(X_test, y_test)) == pytest.approx(
        float(expected.score(X_test, y_test)), abs=1e-12
    )

    assert len(classifier.estimators_) == len(expected_classifier.estimators_)
    for actual_tree, expected_tree in zip(
        classifier.estimators_, expected_classifier.estimators_
    ):
        np.testing.assert_array_equal(actual_tree.tree_.children_left, expected_tree.tree_.children_left)
        np.testing.assert_array_equal(actual_tree.tree_.children_right, expected_tree.tree_.children_right)
        np.testing.assert_array_equal(actual_tree.tree_.feature, expected_tree.tree_.feature)
        np.testing.assert_allclose(actual_tree.tree_.threshold, expected_tree.tree_.threshold, rtol=0, atol=0)
        np.testing.assert_allclose(actual_tree.tree_.value, expected_tree.tree_.value, rtol=0, atol=0)


def test_train_script_fixed():
    """Verify that train.py is updated to use Pipeline and avoids data leakage."""
    script_path = SCRIPT_PATH
    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    with open(script_path, "r") as f:
        content = f.read()

    assert "Pipeline" in content, "The script does not seem to use a scikit-learn Pipeline."
    assert "imputer.fit_transform(X)" not in content, (
        "Data leak still present: imputer.fit_transform(X) found."
    )
    assert "scaler.fit_transform(X_imputed)" not in content, (
        "Data leak still present: scaler.fit_transform(X_imputed) found."
    )
    assert "train_test_split(X," in content.replace(" ", "") or "train_test_split(X," in content, (
        "train_test_split should split the original X, not scaled data."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
