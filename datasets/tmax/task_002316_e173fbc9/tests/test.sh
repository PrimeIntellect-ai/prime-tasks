#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import random
import secrets
import tempfile

import numpy as np
import pandas as pd
import pytest
import requests
from scipy.sparse import hstack
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import cross_val_score

ABSTRACTS = [
    "This is a great paper on AI.",
    "A novel framework for deep learning.",
    "Bad paper with no results.",
    "An analysis of something.",
    "More research is needed.",
    "Another abstract here.",
    "Something else.",
    "Yet another paper.",
    "Final paper.",
    "One more for good measure.",
]
CITATIONS = [10, 0, 0, 0, 5, 12, 0, 2, 0, 3]
LABELS = [1, 1, 0, 0, 1, 1, 0, 0, 1, 1]
TOKEN = "Bearer ds-research-token-881"
URL = "http://127.0.0.1:5000/predict"


def make_reference():
    vectorizer = TfidfVectorizer(max_features=100, stop_words="english")
    text_features = vectorizer.fit_transform(ABSTRACTS)
    features = hstack([
        text_features,
        np.asarray(CITATIONS, dtype=int).reshape(-1, 1),
    ], format="csr")
    labels = np.asarray(LABELS, dtype=int)
    model = LogisticRegression()
    model.fit(features, labels)
    return vectorizer, model, features, labels


def reference_prediction(vectorizer, model, abstract, citations):
    text_features = vectorizer.transform([abstract])
    features = hstack([
        text_features,
        np.asarray([[citations]], dtype=int),
    ], format="csr")
    return int(model.predict(features)[0])


def authorized_predict(payload):
    try:
        response = requests.post(
            URL,
            json=payload,
            headers={"Authorization": TOKEN},
            timeout=5,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the web service at {URL}: {exc}")

    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "prediction" in data, f"Key 'prediction' missing from response JSON: {data}"
    assert data["prediction"] in (0, 1), (
        f"Prediction value should be 0 or 1, got {data['prediction']}"
    )
    return data["prediction"]


def test_preprocess_fixed():
    """Verify the bug in textprep_lib is fixed and it handles 'None' correctly."""
    sys.path.insert(0, "/app/textprep_lib-0.4.5")
    try:
        from textprep_lib.preprocess import load_and_clean
    except ImportError:
        pytest.fail("Could not import textprep_lib.preprocess. Was it fixed and structured correctly?")

    with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
        f.write("abstract,citations,is_accepted\n")
        f.write("test paper 1,None,1\n")
        f.write("test paper 2,5,0\n")
        temp_path = f.name

    try:
        df = load_and_clean(temp_path)
        assert "citations" in df.columns, "citations column missing after load_and_clean"
        assert df.loc[0, "citations"] == 0, "String 'None' was not replaced by 0"
        assert pd.api.types.is_integer_dtype(df["citations"]), (
            f"citations column is not integer type, got {df['citations'].dtype}"
        )
    finally:
        os.remove(temp_path)


def test_cv_result_exists_and_valid():
    """Verify the saved result equals the required five-fold CV computation."""
    path = "/home/user/cv_result.txt"
    assert os.path.isfile(path), f"CV result file {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"CV result file does not contain a valid float. Found: {content}")

    assert 0.0 <= val <= 1.0, f"CV accuracy should be between 0.0 and 1.0, got {val}"

    _, _, features, labels = make_reference()
    expected = float(cross_val_score(
        LogisticRegression(), features, labels, cv=5, scoring="accuracy"
    ).mean())
    assert np.isclose(val, expected, rtol=0.0, atol=1e-12), (
        f"CV result {val} does not match the required five-fold mean accuracy {expected}"
    )


def test_web_service_auth_missing():
    payload = {"abstract": "A novel framework for...", "citations": 12}
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the web service at {URL}: {exc}")
    assert response.status_code in (401, 403), (
        f"Expected 401 or 403 for missing auth, got {response.status_code}"
    )


def test_web_service_auth_wrong():
    payload = {"abstract": "A novel framework for...", "citations": 12}
    headers = {"Authorization": "Bearer wrong-token"}
    try:
        response = requests.post(URL, json=payload, headers=headers, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the web service at {URL}: {exc}")
    assert response.status_code in (401, 403), (
        f"Expected 401 or 403 for wrong auth, got {response.status_code}"
    )


def test_web_service_success():
    payload = {"abstract": "A novel framework for deep learning models.", "citations": 42}
    prediction = authorized_predict(payload)
    assert prediction in (0, 1)


def test_web_service_matches_trained_pipeline_on_challenges():
    """Exercise the service against independently trained TF-IDF/LR predictions."""
    vectorizer, model, _, _ = make_reference()
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))

    candidates = []
    for _ in range(80):
        base = rng.choice(ABSTRACTS)
        abstract = f"{base} validation-{secrets.token_hex(6)}"
        citations = rng.randint(-60, 80)
        expected = reference_prediction(vectorizer, model, abstract, citations)
        candidates.append((abstract, citations, expected))

    by_class = {
        cls: [item for item in candidates if item[2] == cls]
        for cls in (0, 1)
    }
    assert by_class[0] and by_class[1], "Reference model did not yield both classes"

    probes = rng.sample(by_class[0], min(4, len(by_class[0])))
    probes += rng.sample(by_class[1], min(4, len(by_class[1])))

    # If integer-valued citations expose a text-dependent decision, include two
    # abstracts at the same citation count to verify that TF-IDF is actually used.
    text_pair = None
    for citations in range(-100, 101):
        predictions = [
            reference_prediction(vectorizer, model, abstract, citations)
            for abstract in ABSTRACTS
        ]
        if len(set(predictions)) > 1:
            zero_index = predictions.index(0)
            one_index = predictions.index(1)
            text_pair = [
                (ABSTRACTS[zero_index], citations, 0),
                (ABSTRACTS[one_index], citations, 1),
            ]
            break
    if text_pair:
        probes.extend(text_pair)

    rng.shuffle(probes)
    for abstract, citations, expected in probes:
        actual = authorized_predict({"abstract": abstract, "citations": citations})
        assert actual == expected, (
            "Service prediction does not match the required trained TF-IDF/"
            f"LogisticRegression model for citations={citations}: "
            f"expected {expected}, got {actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
