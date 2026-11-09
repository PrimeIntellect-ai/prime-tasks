#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import re
import time

import numpy as np
import pandas as pd
import pytest
import pytesseract
import requests
from PIL import Image
from sklearn.decomposition import PCA
from sklearn.model_selection import GridSearchCV
from sklearn.neighbors import KNeighborsClassifier
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

URL = "http://127.0.0.1:8000/recommend"


def post_recommend(features):
    response = None
    for i in range(5):
        try:
            response = requests.post(URL, json={"features": features}, timeout=5)
            break
        except requests.exceptions.RequestException:
            if i == 4:
                pytest.fail("Failed to connect to the API server at 127.0.0.1:8000. Ensure the server is running and bound to the correct host and port.")
            time.sleep(1)
    return response


def assert_basic_response(response):
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert "recommended_class" in data, "Response JSON missing 'recommended_class' key"
    assert "similar_ids" in data, "Response JSON missing 'similar_ids' key"
    assert isinstance(data["recommended_class"], int), f"'recommended_class' should be an integer, got {type(data['recommended_class'])}"
    assert isinstance(data["similar_ids"], list), f"'similar_ids' should be a list, got {type(data['similar_ids'])}"
    assert len(data["similar_ids"]) in [3, 5], f"Expected 'similar_ids' length to be 3 or 5 (from K_NEIGHBORS grid), got {len(data['similar_ids'])}"
    for item in data["similar_ids"]:
        assert isinstance(item, int), f"All items in 'similar_ids' should be integers, found {type(item)}"
    return data


def read_hyperparameters():
    text = pytesseract.image_to_string(Image.open("/app/hyperparameters.png"))
    cv_match = re.search(r"CV_FOLDS\s*=\s*(\d+)", text, re.I)
    pca_match = re.search(r"PCA_COMPONENTS\s*=\s*\[([^]]+)\]", text, re.I)
    knn_match = re.search(r"K_NEIGHBORS\s*=\s*\[([^]]+)\]", text, re.I)
    assert cv_match and pca_match and knn_match, f"Could not parse hyperparameters image; OCR text was: {text!r}"

    parse_list = lambda match: [int(x) for x in re.findall(r"\d+", match.group(1))]
    return int(cv_match.group(1)), parse_list(pca_match), parse_list(knn_match)


def build_reference():
    cv_folds, pca_components, k_neighbors = read_hyperparameters()
    frame = pd.read_csv("/app/data.csv").dropna(axis=0, how="any").copy()
    features = [f"f{i}" for i in range(1, 11)]
    X = frame[features].astype(float)
    y = frame["target"].astype(int)

    pipeline = Pipeline([
        ("scaler", StandardScaler()),
        ("pca", PCA()),
        ("knn", KNeighborsClassifier()),
    ])
    search = GridSearchCV(
        pipeline,
        {
            "pca__n_components": pca_components,
            "knn__n_neighbors": k_neighbors,
        },
        cv=cv_folds,
        scoring="accuracy",
    )
    search.fit(X, y)
    return frame, X, search.best_estimator_


@pytest.fixture(scope="module")
def reference():
    return build_reference()


def test_recommend_endpoint():
    # Preserve the original fixed-payload and response-shape assertions.
    response = post_recommend([0.1] * 10)
    assert_basic_response(response)


def test_recommendations_match_cleaned_tuned_pipeline(reference):
    frame, X, model = reference
    scaler = model.named_steps["scaler"]
    pca = model.named_steps["pca"]
    knn = model.named_steps["knn"]
    cleaned_ids = frame["id"].astype(int).to_numpy()
    best_k = int(knn.n_neighbors)

    # Include real cleaned rows and deterministic off-dataset points spanning the
    # feature distribution, so predictions, neighbor identities, and ordering are
    # all exercised rather than merely checking a response shape.
    row_positions = np.linspace(0, len(X) - 1, 6, dtype=int)
    probes = [X.iloc[i].to_numpy(dtype=float) for i in row_positions]

    seed_material = open("/app/data.csv", "rb").read() + open("/app/hyperparameters.png", "rb").read()
    seed = int.from_bytes(hashlib.sha256(seed_material).digest()[:8], "big")
    rng = np.random.default_rng(seed)
    means = X.mean(axis=0).to_numpy(dtype=float)
    scales = X.std(axis=0, ddof=0).to_numpy(dtype=float)
    probes.extend(means + rng.normal(size=10) * scales * 1.5 for _ in range(8))
    probes.extend([
        np.zeros(10, dtype=float),
        X.quantile(0.25).to_numpy(dtype=float),
        X.quantile(0.75).to_numpy(dtype=float),
    ])

    transformed_training = pca.transform(scaler.transform(X))

    for probe in probes:
        query = np.asarray(probe, dtype=float).reshape(1, -1)
        expected_class = int(model.predict(query)[0])
        transformed_query = pca.transform(scaler.transform(query))
        neighbor_positions = knn.kneighbors(
            transformed_query, n_neighbors=best_k, return_distance=False
        )[0]
        expected_ids = [int(cleaned_ids[i]) for i in neighbor_positions]

        response = post_recommend(query[0].tolist())
        data = assert_basic_response(response)
        assert len(data["similar_ids"]) == best_k, (
            f"Expected {best_k} neighbors from the selected K_NEIGHBORS value, "
            f"got {len(data['similar_ids'])}"
        )
        assert data["recommended_class"] == expected_class, (
            f"Incorrect predicted class for features {query[0].tolist()}: "
            f"expected {expected_class}, got {data['recommended_class']}"
        )
        assert data["similar_ids"] == expected_ids, (
            f"Incorrect nearest-neighbor IDs or ordering for features {query[0].tolist()}: "
            f"expected {expected_ids}, got {data['similar_ids']}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
