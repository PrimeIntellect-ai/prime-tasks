#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import importlib.metadata
import json
import math
import os
import re
import secrets

import numpy as np
import pytest
import requests
from sklearn.linear_model import Ridge

RESULTS_PATH = "/home/user/experiment_results.json"
DATA_PATH = "/home/user/data/messy_data.csv"
UTILS_PATH = "/app/text-cleaner-pro/text_cleaner_pro/utils.py"
URL = "http://127.0.0.1:8080/predict"
API_KEY = "DS-CLEAN-2024"


def reference_clean(text):
    return re.sub(r"[^a-z0-9 ]", "", text.lower().strip()).strip()


def reference_embedding(text):
    seed = sum(ord(c) for c in text)
    return np.random.RandomState(seed).randn(64)


def build_reference_model():
    cleaned = []
    targets = []
    with open(DATA_PATH, newline="") as f:
        for row in csv.DictReader(f):
            cleaned.append(reference_clean(row["text"]))
            targets.append(float(row["target"]))

    features = np.vstack([reference_embedding(text) for text in cleaned])
    targets = np.asarray(targets, dtype=float)
    model = Ridge(alpha=1.0)
    model.fit(features, targets)
    predictions = model.predict(features)
    mse = float(np.mean((predictions - targets) ** 2))
    return model, mse


REFERENCE_MODEL, EXPECTED_MSE = build_reference_model()


def authorized_request(text):
    try:
        return requests.post(
            URL,
            json={"text": text},
            headers={"X-API-Key": API_KEY},
            timeout=5,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the API at {URL}. Is the server running? Error: {exc}")


def assert_valid_prediction_response(response, raw_text):
    assert response.status_code == 200, (
        f"Expected 200 OK for authorized request, got {response.status_code}. "
        f"Response body: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"API response is not valid JSON. Response body: {response.text}")

    assert "cleaned_text" in data, "Key 'cleaned_text' missing from API response."
    assert "prediction" in data, "Key 'prediction' missing from API response."
    assert data["cleaned_text"] == reference_clean(raw_text), (
        f"Expected cleaned text '{reference_clean(raw_text)}', got '{data['cleaned_text']}'"
    )
    assert isinstance(data["prediction"], float), "Prediction must be a float."
    assert math.isfinite(data["prediction"]), "Prediction must be finite."

    expected = float(
        REFERENCE_MODEL.predict(reference_embedding(reference_clean(raw_text)).reshape(1, -1))[0]
    )
    assert math.isclose(data["prediction"], expected, rel_tol=1e-6, abs_tol=1e-6), (
        f"Prediction {data['prediction']} does not match the Ridge model prediction {expected}."
    )


def test_vendored_package_fixed_and_installed():
    assert os.path.isfile(UTILS_PATH), "Vendored package utils.py is missing."
    with open(UTILS_PATH, "r") as f:
        tree = ast.parse(f.read(), filename=UTILS_PATH)

    dimensions = []
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "EMBEDDING_DIM":
                    dimensions.append(ast.literal_eval(node.value))
    assert dimensions and dimensions[-1] == 64, "EMBEDDING_DIM in the vendored package must be fixed to 64."

    try:
        importlib.metadata.version("text-cleaner-pro")
    except importlib.metadata.PackageNotFoundError:
        pytest.fail("The vendored text-cleaner-pro package was not installed.")

    from text_cleaner_pro.core import clean_text, get_embedding
    from text_cleaner_pro.utils import EMBEDDING_DIM

    assert EMBEDDING_DIM == 64
    assert clean_text("  HELLO world!  ") == "hello world"
    for raw in ("data science is fun", "Verifier check 42!"):
        cleaned = reference_clean(raw)
        actual = np.asarray(get_embedding(cleaned), dtype=float)
        assert actual.shape == (64,), "get_embedding must return a 64-dimensional vector."
        np.testing.assert_allclose(actual, reference_embedding(cleaned), rtol=0, atol=1e-12)


def test_experiment_results_exists_and_valid():
    assert os.path.exists(RESULTS_PATH), (
        f"Results file {RESULTS_PATH} is missing. Did you save the experiment results?"
    )
    with open(RESULTS_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Experiment results file {RESULTS_PATH} is not valid JSON.")

    assert "train_mse" in data, "Key 'train_mse' is missing from experiment results JSON."
    assert isinstance(data["train_mse"], float), "Value for 'train_mse' must be a float."
    assert math.isfinite(data["train_mse"]), "Value for 'train_mse' must be finite."
    assert math.isclose(data["train_mse"], EXPECTED_MSE, rel_tol=1e-9, abs_tol=1e-12), (
        f"Saved train_mse {data['train_mse']} does not match the recomputed Ridge training MSE "
        f"{EXPECTED_MSE}."
    )


def test_api_unauthorized_access():
    payload = {"text": "Data SCIENCE is fun."}
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the API at {URL}. Is the server running? Error: {exc}")
    assert response.status_code in (401, 403), (
        f"Expected 401 or 403 for request without API key, got {response.status_code}. "
        f"Response body: {response.text}"
    )

    response = requests.post(
        URL,
        json=payload,
        headers={"X-API-Key": "wrong-key"},
        timeout=5,
    )
    assert response.status_code in (401, 403), "An invalid API key must be rejected."


def test_api_authorized_access_and_prediction():
    raw_text = "Data SCIENCE is fun."
    response = authorized_request(raw_text)
    assert_valid_prediction_response(response, raw_text)


def test_api_predictions_on_runtime_generated_inputs():
    nonce = secrets.token_hex(10)
    inputs = [
        f"  Novel INPUT-{nonce}!!  ",
        f"Symbols### and Mixed CASE {nonce[::-1]}?",
        f"embedding regression check {nonce} 2024",
    ]
    for raw_text in inputs:
        assert_valid_prediction_response(authorized_request(raw_text), raw_text)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
