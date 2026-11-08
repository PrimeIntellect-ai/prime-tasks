#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os

import numpy as np
import pytest
from sklearn.decomposition import TruncatedSVD
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression

DOCUMENTS = [
    {"id": 1, "text": "machine learning is fascinating", "label": 1},
    {"id": 2, "text": "artificial intelligence models", "label": 1},
    {"id": 3, "text": "the weather is nice today", "label": 0},
    {"id": 4, "text": "deep learning neural networks", "label": 1},
    {"id": 5, "text": "i like to eat apples", "label": 0},
    {"id": 6, "text": "data science and predictive modeling", "label": 1},
    {"id": 7, "text": "going for a walk outside", "label": 0},
    {"id": 8, "text": "support vector machines in python", "label": 1},
    {"id": 9, "text": "cooking dinner in the kitchen", "label": 0},
    {"id": 10, "text": "gradient boosting trees", "label": 1},
]
CATEGORY_BY_ID = {1: 10, 2: 10, 3: 20, 4: 10, 5: -1, 6: 10, 7: 20, 8: 10, 9: 20, 10: -1}


def expected_pipeline():
    texts = [row["text"] for row in DOCUMENTS]
    tfidf = TfidfVectorizer(stop_words="english", max_features=50).fit_transform(texts)
    svd = TruncatedSVD(n_components=3, random_state=42).fit_transform(tfidf)
    categories = np.array([CATEGORY_BY_ID[row["id"]] for row in DOCUMENTS], dtype=int)
    labels = np.array([row["label"] for row in DOCUMENTS], dtype=int)
    model_input = np.column_stack([svd, categories])
    model = LogisticRegression(random_state=42)
    model.fit(model_input, labels)
    return svd, float(model.score(model_input, labels))


EXPECTED_SVD, EXPECTED_ACCURACY = expected_pipeline()
EXPECTED_ROW_BY_ID = {
    row["id"]: (EXPECTED_SVD[index], CATEGORY_BY_ID[row["id"]])
    for index, row in enumerate(DOCUMENTS)
}


def test_features_jsonl_exists_and_valid():
    file_path = "/home/user/output/features.jsonl"
    assert os.path.isfile(file_path), f"{file_path} is missing"

    with open(file_path, "r") as f:
        lines = f.readlines()

    assert len(lines) == 10, "features.jsonl should have exactly 10 lines"

    parsed_ids = set()
    parsed_rows = {}
    for i, line in enumerate(lines):
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in {file_path} is not valid JSON")

        required_keys = {"id", "svd_0", "svd_1", "svd_2", "category_id"}
        missing_keys = required_keys - set(obj.keys())
        assert not missing_keys, f"Line {i+1} is missing keys: {missing_keys}"

        parsed_ids.add(obj["id"])
        assert obj["id"] not in parsed_rows, f"Duplicate id {obj['id']} in features.jsonl"
        parsed_rows[obj["id"]] = obj

        cat_id = obj["category_id"]
        assert isinstance(cat_id, int), f"category_id must be an integer, got {type(cat_id)} on line {i+1}"
        assert not isinstance(cat_id, bool), f"category_id must be an integer, got bool on line {i+1}"

        if obj["id"] in (5, 10):
            assert cat_id == -1, f"category_id for id {obj['id']} should be -1, got {cat_id}"

        for key in ("svd_0", "svd_1", "svd_2"):
            value = obj[key]
            assert isinstance(value, (int, float)), f"{key} must be a number on line {i+1}"
            assert not isinstance(value, bool), f"{key} must be a number, not bool, on line {i+1}"
            assert math.isfinite(value), f"{key} must be finite on line {i+1}"

    assert parsed_ids == set(range(1, 11)), "features.jsonl must contain all ids from 1 to 10"

    for doc_id in range(1, 11):
        obj = parsed_rows[doc_id]
        expected_svd, expected_category = EXPECTED_ROW_BY_ID[doc_id]
        assert obj["category_id"] == expected_category, (
            f"category_id for id {doc_id} should be {expected_category}, got {obj['category_id']}"
        )
        actual_svd = np.array([obj["svd_0"], obj["svd_1"], obj["svd_2"]], dtype=float)
        np.testing.assert_allclose(
            actual_svd,
            expected_svd,
            rtol=1e-7,
            atol=1e-7,
            err_msg=f"Incorrect TF-IDF/SVD features for id {doc_id}",
        )


def test_accuracy_txt_exists_and_valid():
    file_path = "/home/user/output/accuracy.txt"
    assert os.path.isfile(file_path), f"{file_path} is missing"

    with open(file_path, "r") as f:
        content = f.read().strip()

    try:
        accuracy = float(content)
    except ValueError:
        pytest.fail(f"accuracy.txt must contain a valid float, got: {content}")

    assert 0.0 <= accuracy <= 1.0, f"accuracy must be between 0.0 and 1.0, got: {accuracy}"
    assert math.isfinite(accuracy), f"accuracy must be finite, got: {accuracy}"
    assert accuracy == pytest.approx(EXPECTED_ACCURACY, abs=1e-12), (
        f"accuracy must equal the recomputed training accuracy {EXPECTED_ACCURACY}, got {accuracy}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
