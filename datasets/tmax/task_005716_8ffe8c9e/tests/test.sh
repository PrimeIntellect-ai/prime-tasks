#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess
import sys

import numpy as np
import pytest
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity


@pytest.fixture(scope="session", autouse=True)
def execute_and_validate_pipeline():
    fixed_path = "/home/user/fixed_pipeline.py"
    train_path = "/home/user/train_data.json"
    query_path = "/home/user/query_data.json"
    v2_path = "/home/user/experiment_v2.json"

    assert os.path.isfile(fixed_path), f"Missing file: {fixed_path}"

    with open(train_path, "rb") as f:
        original_train = f.read()
    with open(query_path, "rb") as f:
        original_queries = f.read()

    # Use unpredictable tokens in a corpus where fitting on the queries produces
    # a measurably different answer from fitting on the training data alone.
    token = lambda: "tok" + secrets.token_hex(12)
    shared, apple, orchard, banana, carrot, garden = [token() for _ in range(6)]
    unseen = [token() for _ in range(5)]
    challenge_train = [
        f"{shared} {apple} {orchard}",
        f"{shared} {banana} {banana}",
        f"{carrot} {garden}",
    ]
    challenge_queries = [
        f"{shared} {apple} {unseen[0]} {unseen[1]} {unseen[2]}",
        f"{banana} {unseen[3]} {unseen[4]}",
    ]

    try:
        with open(train_path, "w") as f:
            json.dump(challenge_train, f)
        with open(query_path, "w") as f:
            json.dump(challenge_queries, f)
        if os.path.exists(v2_path):
            os.remove(v2_path)

        subprocess.run(
            [sys.executable, fixed_path],
            cwd="/home/user",
            check=True,
            timeout=30,
        )
        assert os.path.isfile(v2_path), "fixed_pipeline.py did not create experiment_v2.json"
        with open(v2_path, "r") as f:
            challenge_result = json.load(f)
        assert "avg_top1_similarity" in challenge_result
        actual = challenge_result["avg_top1_similarity"]
        assert isinstance(actual, (int, float)) and math.isfinite(actual)

        vectorizer = TfidfVectorizer()
        train_vecs = vectorizer.fit_transform(challenge_train)
        query_vecs = vectorizer.transform(challenge_queries)
        expected = float(np.mean(np.max(cosine_similarity(query_vecs, train_vecs), axis=1)))

        leaky_vectorizer = TfidfVectorizer()
        leaky_vectorizer.fit(challenge_train + challenge_queries)
        leaky = float(np.mean(np.max(cosine_similarity(
            leaky_vectorizer.transform(challenge_queries),
            leaky_vectorizer.transform(challenge_train),
        ), axis=1)))
        assert not math.isclose(expected, leaky, rel_tol=1e-6, abs_tol=1e-8), "Verifier challenge was not discriminative"
        assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-12), (
            f"fixed_pipeline.py produced {actual}; training-only TF-IDF expected {expected}"
        )
    finally:
        with open(train_path, "wb") as f:
            f.write(original_train)
        with open(query_path, "wb") as f:
            f.write(original_queries)

    # Re-run both pipelines on the supplied data so the required artifacts are
    # fresh before applying the original output assertions.
    subprocess.run(
        [sys.executable, "/home/user/etl_pipeline.py"],
        cwd="/home/user",
        check=True,
        timeout=30,
    )
    subprocess.run(
        [sys.executable, fixed_path],
        cwd="/home/user",
        check=True,
        timeout=30,
    )


def test_fixed_pipeline_exists():
    file_path = "/home/user/fixed_pipeline.py"
    assert os.path.exists(file_path), f"Missing file: {file_path}"
    assert os.path.isfile(file_path), f"Not a file: {file_path}"
    with open(file_path, "r") as f:
        content = f.read()
        assert "experiment_v2.json" in content, "fixed_pipeline.py should reference experiment_v2.json"


def test_experiment_v1_output():
    file_path = "/home/user/experiment_v1.json"
    assert os.path.exists(file_path), f"Missing file: {file_path}"
    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Invalid JSON in {file_path}"
    assert "avg_top1_similarity" in data, f"Missing 'avg_top1_similarity' in {file_path}"
    v1 = data["avg_top1_similarity"]
    assert math.isclose(v1, 0.4485590396440231, rel_tol=1e-5), f"Expected avg_top1_similarity in v1 to be ~0.448559, got {v1}"


def test_experiment_v2_output():
    file_path = "/home/user/experiment_v2.json"
    assert os.path.exists(file_path), f"Missing file: {file_path}"
    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Invalid JSON in {file_path}"
    assert "avg_top1_similarity" in data, f"Missing 'avg_top1_similarity' in {file_path}"
    v2 = data["avg_top1_similarity"]
    assert math.isclose(v2, 0.4194511565268481, rel_tol=1e-5), f"Expected avg_top1_similarity in v2 to be ~0.419451, got {v2}"


def test_leakage_diff_output():
    file_path = "/home/user/leakage_diff.txt"
    assert os.path.exists(file_path), f"Missing file: {file_path}"
    with open(file_path, "r") as f:
        content = f.read().strip()

    try:
        diff = float(content)
    except ValueError:
        assert False, f"Could not parse float from {file_path}. Content: '{content}'"

    with open("/home/user/experiment_v1.json", "r") as f:
        v1 = json.load(f)["avg_top1_similarity"]
    with open("/home/user/experiment_v2.json", "r") as f:
        v2 = json.load(f)["avg_top1_similarity"]

    expected_diff = abs(v1 - v2)
    assert math.isclose(diff, expected_diff, rel_tol=1e-5), f"Expected difference to be ~{expected_diff}, got {diff}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
