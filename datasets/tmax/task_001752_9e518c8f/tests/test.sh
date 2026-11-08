#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "joblib:joblib"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile
from collections import Counter

import joblib
import numpy as np
import pandas as pd
import pytest
import requests
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression

BASE = "/app/text_prep_serve"


def build_expected():
    texts = pd.read_csv(os.path.join(BASE, "data/texts.csv"))
    labels = pd.read_csv(os.path.join(BASE, "data/labels.csv"))
    df = pd.merge(texts, labels, on="id")

    split_idx = int(len(df) * 0.8)
    train_text = df["text"].iloc[:split_idx]
    test_text = df["text"].iloc[split_idx:]
    y_train = df["label"].values[:split_idx]

    vectorizer = TfidfVectorizer()
    X_train = vectorizer.fit_transform(train_text)
    X_test = vectorizer.transform(test_text)

    np.random.seed(42)
    models = []
    bootstrap_indices = []
    for _ in range(3):
        idx = np.random.choice(len(X_train.toarray()), len(X_train.toarray()), replace=True)
        bootstrap_indices.append(idx)
        model = LogisticRegression()
        model.fit(X_train[idx], y_train[idx])
        models.append(model)

    return vectorizer, models, X_test, bootstrap_indices


EXPECTED_VECTORIZER, EXPECTED_MODELS, EXPECTED_TEST_X, EXPECTED_BOOTSTRAPS = build_expected()


def assert_artifacts(models_dir):
    assert os.path.isdir(models_dir), f"{models_dir} directory is missing"
    files = os.listdir(models_dir)
    assert len(files) > 0, "No models or vectorizer found in the models directory"

    expected_paths = [os.path.join(models_dir, "vectorizer.pkl")]
    expected_paths += [os.path.join(models_dir, f"model_{i}.pkl") for i in range(3)]
    for path in expected_paths:
        assert os.path.isfile(path), f"Required artifact is missing: {path}"
        assert os.path.getsize(path) > 0, f"Artifact is empty: {path}"

    vectorizer = joblib.load(expected_paths[0])
    assert isinstance(vectorizer, TfidfVectorizer), "vectorizer.pkl is not a TfidfVectorizer"
    assert vectorizer.vocabulary_ == EXPECTED_VECTORIZER.vocabulary_, \
        "The learned vocabulary is not the vocabulary from the first 80% of rows"
    assert set(vectorizer.get_feature_names_out()) == {"apple", "banana", "orange"}
    assert "rareword" not in vectorizer.vocabulary_
    assert "testword" not in vectorizer.vocabulary_
    np.testing.assert_allclose(vectorizer.idf_, EXPECTED_VECTORIZER.idf_, rtol=1e-10, atol=1e-12)

    submitted_models = []
    for i, expected in enumerate(EXPECTED_MODELS):
        model = joblib.load(os.path.join(models_dir, f"model_{i}.pkl"))
        assert isinstance(model, LogisticRegression), f"model_{i}.pkl is not LogisticRegression"
        assert hasattr(model, "coef_") and hasattr(model, "intercept_")
        np.testing.assert_array_equal(model.classes_, expected.classes_)
        np.testing.assert_allclose(model.coef_, expected.coef_, rtol=1e-9, atol=1e-11)
        np.testing.assert_allclose(model.intercept_, expected.intercept_, rtol=1e-9, atol=1e-11)
        submitted_models.append(model)

    probes = [
        "apple orange", "banana orange", "apple banana", "apple",
        "banana", "orange", "rareword testword", "completely unseen tokens",
        "apple apple orange", "banana banana orange"
    ]
    expected_x = EXPECTED_VECTORIZER.transform(probes)
    actual_x = vectorizer.transform(probes)
    np.testing.assert_allclose(actual_x.toarray(), expected_x.toarray(), rtol=1e-10, atol=1e-12)
    for actual, expected in zip(submitted_models, EXPECTED_MODELS):
        np.testing.assert_array_equal(actual.predict(actual_x), expected.predict(expected_x))


def expected_prediction(text):
    X = EXPECTED_VECTORIZER.transform([text])
    predictions = [int(model.predict(X)[0]) for model in EXPECTED_MODELS]
    return Counter(predictions).most_common(1)[0][0]


def test_makefile_fixed():
    makefile_path = os.path.join(BASE, "Makefile")
    assert os.path.isfile(makefile_path), "Makefile is missing"
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "requirements.txt" in content, "Makefile was not fixed to use 'requirements.txt'"
    assert "requirments.txt" not in content, "Makefile still contains the typo 'requirments.txt'"

    result = subprocess.run(
        ["make", "-n", "install"], cwd=BASE, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10
    )
    assert result.returncode == 0, f"Makefile install target is invalid:\n{result.stdout}"
    assert re.search(r"pip(?:3)?\s+install\s+-r\s+(?:\./)?requirements\.txt(?:\s|$)", result.stdout), \
        f"install target does not install requirements.txt:\n{result.stdout}"


def test_prepare_script_fixed():
    prepare_path = os.path.join(BASE, "src/prepare.py")
    assert os.path.isfile(prepare_path), "prepare.py is missing"
    with open(prepare_path, "r") as f:
        content = f.read()

    # Retain the original source-level assertion, while behavioral tests below
    # ensure these words correspond to the required operations.
    assert re.search(r"fit_transform\s*\(.*train", content, re.IGNORECASE) or \
           "fit_transform" in content and "transform" in content, \
           "prepare.py does not seem to properly separate fit_transform for train and transform for test"

    # Execute prepare.py in a clean package layout so pre-existing artifacts
    # cannot satisfy this test.
    with tempfile.TemporaryDirectory() as tmp:
        package = os.path.join(tmp, "text_prep_serve")
        os.makedirs(os.path.join(package, "src"))
        os.makedirs(os.path.join(package, "data"))
        shutil.copy2(prepare_path, os.path.join(package, "src", "prepare.py"))
        shutil.copy2(os.path.join(BASE, "data/texts.csv"), os.path.join(package, "data", "texts.csv"))
        shutil.copy2(os.path.join(BASE, "data/labels.csv"), os.path.join(package, "data", "labels.csv"))

        result = subprocess.run(
            ["python3", "prepare.py"], cwd=os.path.join(package, "src"),
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
        )
        assert result.returncode == 0, f"prepare.py failed in a clean layout:\n{result.stdout}"
        assert_artifacts(os.path.join(package, "models"))


def test_models_generated():
    assert_artifacts(os.path.join(BASE, "models"))


def test_api_server_predict():
    url = "http://127.0.0.1:8000/predict"
    probe_texts = [
        "unseen test document with rare words",
        "apple orange",
        "banana orange",
        "apple banana",
        "apple apple apple orange",
        "banana banana banana orange",
        "rareword testword",
        "orange",
        "apple rareword",
        "banana testword",
        "apple banana orange",
        "totally unknown vocabulary"
    ]

    expected_values = {expected_prediction(text) for text in probe_texts}
    assert expected_values == {0, 1}, "Internal test probes must exercise both ensemble outputs"

    for text in probe_texts:
        try:
            response = requests.post(url, json={"text": text}, timeout=5)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to the API server at {url}: {e}")

        assert response.status_code == 200, \
            f"Expected status code 200, got {response.status_code}. Response: {response.text}"
        data = response.json()
        assert "prediction" in data, "Response JSON missing 'prediction' key"
        assert isinstance(data["prediction"], int), "Prediction must be an integer"
        assert data["prediction"] == expected_prediction(text), \
            f"Wrong ensemble prediction for {text!r}: {data['prediction']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
