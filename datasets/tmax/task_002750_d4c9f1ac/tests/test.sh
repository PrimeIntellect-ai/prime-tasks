#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import subprocess

import joblib
import numpy as np
import pandas as pd
import pytest
from sklearn.datasets import make_classification
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

PROJECT_DIR = "/home/user/data_project"
METRICS_PATH = os.path.join(PROJECT_DIR, "metrics.json")
MODEL_PATH = os.path.join(PROJECT_DIR, "model.pkl")
DATASET_PATH = os.path.join(PROJECT_DIR, "dataset.csv")


@pytest.fixture(scope="session", autouse=True)
def run_submission():
    for path in (DATASET_PATH, METRICS_PATH, MODEL_PATH):
        if os.path.exists(path):
            os.remove(path)

    generated = subprocess.run(
        ["python3", os.path.join(PROJECT_DIR, "generate_data.py")],
        cwd=PROJECT_DIR,
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert generated.returncode == 0, (
        f"generate_data.py failed:\nSTDOUT:\n{generated.stdout}\nSTDERR:\n{generated.stderr}"
    )
    assert os.path.isfile(DATASET_PATH), "generate_data.py did not create dataset.csv"

    # Ensure the training run is exercised on the dataset specified by the task.
    actual = pd.read_csv(DATASET_PATH)
    expected_X, expected_y = make_classification(
        n_samples=2000, n_features=60, n_informative=15, random_state=123
    )
    expected_columns = [f"feature_{i}" for i in range(60)] + ["target"]
    assert list(actual.columns) == expected_columns
    assert actual.shape == (2000, 61)
    np.testing.assert_allclose(
        actual.iloc[:, :-1].to_numpy(), expected_X, rtol=1e-12, atol=1e-12
    )
    np.testing.assert_array_equal(actual["target"].to_numpy(), expected_y)

    trained = subprocess.run(
        ["python3", os.path.join(PROJECT_DIR, "train_model.py")],
        cwd=PROJECT_DIR,
        text=True,
        capture_output=True,
        timeout=180,
    )
    assert trained.returncode == 0, (
        f"train_model.py failed:\nSTDOUT:\n{trained.stdout}\nSTDERR:\n{trained.stderr}"
    )


def test_metrics_file_exists_and_valid():
    assert os.path.isfile(METRICS_PATH), f"Metrics file not found at {METRICS_PATH}"

    with open(METRICS_PATH, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {METRICS_PATH} is not valid JSON.")

    assert isinstance(metrics, dict), "Metrics JSON should be an object/dictionary."
    assert "test_accuracy" in metrics, "Key 'test_accuracy' missing in metrics.json"
    assert "pca_explained_variance_1" in metrics, "Key 'pca_explained_variance_1' missing in metrics.json"


def test_metrics_values():
    with open(METRICS_PATH, "r") as f:
        metrics = json.load(f)

    acc = metrics.get("test_accuracy")
    pca_var = metrics.get("pca_explained_variance_1")

    assert isinstance(acc, (int, float)), "test_accuracy must be a number"
    assert isinstance(pca_var, (int, float)), "pca_explained_variance_1 must be a number"
    assert math.isfinite(acc)
    assert math.isfinite(pca_var)

    # Preserve the original expected-value assertions.
    assert math.isclose(acc, 0.875, rel_tol=1e-2), f"test_accuracy {acc} is not close to expected 0.875"
    assert math.isclose(pca_var, 0.063189, rel_tol=1e-2), f"pca_explained_variance_1 {pca_var} is not close to expected 0.063189"


def test_model_file_exists_and_contains_pipeline():
    assert os.path.isfile(MODEL_PATH), f"Model file not found at {MODEL_PATH}"
    assert os.path.getsize(MODEL_PATH) > 0, f"Model file {MODEL_PATH} is empty"

    # Preserve the original binary-content assertions.
    with open(MODEL_PATH, "rb") as f:
        content = f.read()

    assert b"Pipeline" in content, "Model file does not appear to contain a scikit-learn Pipeline"
    assert b"StandardScaler" in content, "Model file does not appear to contain a StandardScaler"
    assert b"PCA" in content, "Model file does not appear to contain a PCA step"
    assert b"LogisticRegression" in content, "Model file does not appear to contain a LogisticRegression step"


def test_deserialized_pipeline_and_derived_results():
    model = joblib.load(MODEL_PATH)
    assert type(model) is Pipeline, "model.pkl must deserialize to a sklearn Pipeline"
    assert len(model.steps) == 3, "Pipeline must contain exactly three steps"

    scaler = model.steps[0][1]
    pca = model.steps[1][1]
    classifier = model.steps[2][1]
    assert type(scaler) is StandardScaler, "First pipeline step must be StandardScaler"
    assert type(pca) is PCA, "Second pipeline step must be PCA"
    assert type(classifier) is LogisticRegression, "Third pipeline step must be LogisticRegression"
    assert pca.n_components == 10, "PCA must use n_components=10"
    assert pca.random_state == 42, "PCA must use random_state=42"
    assert classifier.random_state == 42, "LogisticRegression must use random_state=42"

    df = pd.read_csv(DATASET_PATH)
    X = df.drop("target", axis=1)
    y = df["target"]
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    # Derive the expected fitted pipeline from the required split and parameters.
    reference = Pipeline([
        ("scaler", StandardScaler()),
        ("pca", PCA(n_components=10, random_state=42)),
        ("model", LogisticRegression(random_state=42)),
    ])
    reference.fit(X_train, y_train)

    predictions = model.predict(X_test)
    expected_predictions = reference.predict(X_test)
    np.testing.assert_array_equal(predictions, expected_predictions)

    # These fitted-state comparisons reject preprocessing fitted on the full dataset.
    np.testing.assert_allclose(scaler.mean_, reference.steps[0][1].mean_, rtol=1e-10, atol=1e-12)
    np.testing.assert_allclose(scaler.scale_, reference.steps[0][1].scale_, rtol=1e-10, atol=1e-12)
    np.testing.assert_allclose(
        pca.explained_variance_ratio_,
        reference.steps[1][1].explained_variance_ratio_,
        rtol=1e-9,
        atol=1e-11,
    )
    np.testing.assert_allclose(
        classifier.coef_, reference.steps[2][1].coef_, rtol=1e-8, atol=1e-10
    )

    with open(METRICS_PATH, "r") as f:
        metrics = json.load(f)

    derived_accuracy = accuracy_score(y_test, predictions)
    derived_pca_var = float(pca.explained_variance_ratio_[0])
    assert metrics["test_accuracy"] == pytest.approx(derived_accuracy, rel=1e-12, abs=1e-12)
    assert metrics["pca_explained_variance_1"] == pytest.approx(
        derived_pca_var, rel=1e-12, abs=1e-12
    )


def test_train_model_script_refactored():
    script_path = os.path.join(PROJECT_DIR, "train_model.py")
    assert os.path.isfile(script_path), f"Script not found at {script_path}"

    with open(script_path, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "Pipeline" in content or "make_pipeline" in content, "Script does not seem to use Pipeline"
    assert "scaler.fit_transform(X)" not in content, "Data leak is still present: scaler is fitted on the entire dataset X"
    assert "pca.fit_transform(X_scaled)" not in content, "Data leak is still present: pca is fitted on the entire dataset"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
