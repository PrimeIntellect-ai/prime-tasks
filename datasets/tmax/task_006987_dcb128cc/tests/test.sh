#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import re
import subprocess

import joblib
import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

FIXED_SCRIPT = "/home/user/train_fixed.py"
MODEL_PATH = "/home/user/model_fixed.pkl"
REPORT_PATH = "/home/user/report.json"
FEATURES_PATH = "/home/user/data/features.csv"
LABELS_PATH = "/home/user/data/labels.json"


def load_xy():
    features = pd.read_csv(FEATURES_PATH)
    with open(LABELS_PATH, "r") as f:
        labels = pd.DataFrame(json.load(f))
    merged = pd.merge(features, labels, on="id")
    return merged.drop(columns=["id", "target"]), merged["target"]


def reference_results():
    X, y = load_xy()
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.3, random_state=42
    )

    train_scaler = StandardScaler()
    X_train_scaled = train_scaler.fit_transform(X_train)
    X_test_scaled = train_scaler.transform(X_test)
    reference_model = LogisticRegression(random_state=42)
    reference_model.fit(X_train_scaled, y_train)
    fixed_accuracy = accuracy_score(y_test, reference_model.predict(X_test_scaled))

    leaky_scaler = StandardScaler()
    X_scaled = leaky_scaler.fit_transform(X)
    Xl_train, Xl_test, yl_train, yl_test = train_test_split(
        X_scaled, y, test_size=0.3, random_state=42
    )
    leaky_model = LogisticRegression(random_state=42)
    leaky_model.fit(Xl_train, yl_train)
    leaky_accuracy = accuracy_score(yl_test, leaky_model.predict(Xl_test))

    return {
        "X_train": X_train,
        "X_test": X_test,
        "y_train": y_train,
        "y_test": y_test,
        "scaler": train_scaler,
        "model": reference_model,
        "fixed_accuracy": fixed_accuracy,
        "leaky_accuracy": leaky_accuracy,
    }


def run_script(path):
    return subprocess.run(
        ["python3", path],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
        check=True,
    )


def validate_saved_pipeline(expected):
    assert os.path.isfile(MODEL_PATH), "train_fixed.py did not create model_fixed.pkl"
    assert os.path.getsize(MODEL_PATH) > 0, "model_fixed.pkl is empty"

    artifact = joblib.load(MODEL_PATH)
    assert isinstance(artifact, Pipeline), "model_fixed.pkl must contain a sklearn Pipeline"
    assert len(artifact.steps) == 2, "The saved pipeline must contain exactly the scaler and classifier"
    scaler = artifact.steps[0][1]
    classifier = artifact.steps[1][1]
    assert isinstance(scaler, StandardScaler), "The first pipeline step must be StandardScaler"
    assert isinstance(classifier, LogisticRegression), "The second pipeline step must be LogisticRegression"
    assert classifier.random_state == 42, "LogisticRegression must use random_state=42"

    expected_scaler = expected["scaler"]
    assert scaler.n_samples_seen_ == len(expected["X_train"]), "Scaler was not fit only on the training split"
    np.testing.assert_allclose(scaler.mean_, expected_scaler.mean_, rtol=1e-10, atol=1e-10)
    np.testing.assert_allclose(scaler.var_, expected_scaler.var_, rtol=1e-10, atol=1e-10)

    expected_model = expected["model"]
    np.testing.assert_array_equal(classifier.classes_, expected_model.classes_)
    np.testing.assert_allclose(classifier.coef_, expected_model.coef_, rtol=1e-7, atol=1e-8)
    np.testing.assert_allclose(classifier.intercept_, expected_model.intercept_, rtol=1e-7, atol=1e-8)

    predictions = artifact.predict(expected["X_test"])
    actual_accuracy = accuracy_score(expected["y_test"], predictions)
    assert math.isclose(actual_accuracy, expected["fixed_accuracy"], abs_tol=1e-12)


def test_train_fixed_exists():
    """Verify that train_fixed.py exists."""
    assert os.path.isfile(FIXED_SCRIPT), f"File {FIXED_SCRIPT} is missing. You must create the fixed training script."


def test_model_fixed_exists():
    """Verify that model_fixed.pkl exists."""
    assert os.path.isfile(MODEL_PATH), f"File {MODEL_PATH} is missing. You must save the fixed model pipeline."


def test_fixed_script_executes_and_trains_without_leakage():
    """Execute the submitted script on an unpredictable dataset and validate its fresh artifact."""
    with open(FEATURES_PATH, "rb") as f:
        original_features = f.read()
    with open(LABELS_PATH, "rb") as f:
        original_labels = f.read()

    try:
        features = pd.read_csv(FEATURES_PATH)
        with open(LABELS_PATH, "r") as f:
            labels = json.load(f)

        rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
        feature_columns = [c for c in features.columns if c != "id"]
        values = features[feature_columns].to_numpy(dtype=float)
        scales = rng.uniform(0.35, 3.0, size=values.shape[1])
        offsets = rng.normal(0, 7, size=values.shape[1])
        noise = rng.normal(0, 0.2, size=values.shape)
        features.loc[:, feature_columns] = values * scales + offsets + noise
        features.to_csv(FEATURES_PATH, index=False)

        for item in labels:
            if rng.random() < 0.17:
                item["target"] = 1 - int(item["target"])
        with open(LABELS_PATH, "w") as f:
            json.dump(labels, f)

        expected_challenge = reference_results()
        if os.path.exists(MODEL_PATH):
            os.remove(MODEL_PATH)
        run_script(FIXED_SCRIPT)
        validate_saved_pipeline(expected_challenge)
    finally:
        with open(FEATURES_PATH, "wb") as f:
            f.write(original_features)
        with open(LABELS_PATH, "wb") as f:
            f.write(original_labels)

    expected_original = reference_results()
    if os.path.exists(MODEL_PATH):
        os.remove(MODEL_PATH)
    run_script(FIXED_SCRIPT)
    validate_saved_pipeline(expected_original)

    leaky_run = run_script("/home/user/train.py")
    match = re.search(r"Leaky Accuracy:\s*([0-9]+(?:\.[0-9]+)?)", leaky_run.stdout)
    assert match, "train.py did not print its leaky accuracy"
    assert math.isclose(float(match.group(1)), round(expected_original["leaky_accuracy"], 4), abs_tol=5e-5)


def test_report_json_exists_and_valid():
    """Verify that report.json exists, is valid JSON, and contains the correct keys."""
    assert os.path.isfile(REPORT_PATH), f"File {REPORT_PATH} is missing. You must create the report."
    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_PATH} is not a valid JSON file.")
    assert "leaky_accuracy" in data, "Key 'leaky_accuracy' is missing from report.json."
    assert "fixed_accuracy" in data, "Key 'fixed_accuracy' is missing from report.json."
    assert set(data) == {"leaky_accuracy", "fixed_accuracy"}, "report.json must contain exactly the two required keys."


def test_report_accuracies():
    """Verify that the accuracies in report.json match both the dataset and expected values."""
    if not os.path.isfile(REPORT_PATH):
        pytest.skip("report.json is missing.")
    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.skip("report.json is not valid JSON.")

    leaky_acc = data.get("leaky_accuracy")
    fixed_acc = data.get("fixed_accuracy")
    assert isinstance(leaky_acc, (int, float)) and not isinstance(leaky_acc, bool), "leaky_accuracy must be a number."
    assert isinstance(fixed_acc, (int, float)) and not isinstance(fixed_acc, bool), "fixed_accuracy must be a number."

    expected_leaky = 0.8000
    expected_fixed = 0.7933
    assert math.isclose(leaky_acc, expected_leaky, abs_tol=0.01), f"leaky_accuracy {leaky_acc} is incorrect. Expected ~{expected_leaky}."
    assert math.isclose(fixed_acc, expected_fixed, abs_tol=0.01), f"fixed_accuracy {fixed_acc} is incorrect. Expected ~{expected_fixed}."

    derived = reference_results()
    assert leaky_acc == round(derived["leaky_accuracy"], 4), "leaky_accuracy does not equal the executed pipeline result rounded to 4 decimals."
    assert fixed_acc == round(derived["fixed_accuracy"], 4), "fixed_accuracy does not equal the fixed pipeline result rounded to 4 decimals."
    assert leaky_acc == round(leaky_acc, 4)
    assert fixed_acc == round(fixed_acc, 4)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
