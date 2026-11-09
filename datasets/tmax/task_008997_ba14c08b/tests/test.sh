#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import stat
import string
import subprocess
import sys

import numpy as np
import pytest
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

WORKSPACE_DIR = "/home/user/mlops_workspace"
CORPUS_FILE = os.path.join(WORKSPACE_DIR, "corpus.json")
COMPUTE_SCRIPT = os.path.join(WORKSPACE_DIR, "compute_retrieval.py")
TEST_SCRIPT = os.path.join(WORKSPACE_DIR, "test_accuracy.py")
RESULTS_FILE = os.path.join(WORKSPACE_DIR, "retrieved_pairs.json")


def assert_regular_file(path):
    assert os.path.isfile(path), f"Missing file: {path}"
    assert stat.S_ISREG(os.stat(path, follow_symlinks=False).st_mode), f"Not a regular file: {path}"


def expected_pairs(documents):
    vectors = TfidfVectorizer(stop_words="english").fit_transform(documents)
    similarities = cosine_similarity(vectors)
    np.fill_diagonal(similarities, -np.inf)

    pairs = {}
    for index in range(len(documents)):
        other = int(np.argmax(similarities[index]))
        score = float(similarities[index, other])
        if score >= 0.80:
            key = (min(index, other), max(index, other))
            pairs[key] = round(score, 4)
    return pairs


def validate_results(documents, expected):
    assert_regular_file(RESULTS_FILE)
    with open(RESULTS_FILE, "r", encoding="utf-8") as handle:
        try:
            pairs = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_FILE} is not valid JSON.")

    assert isinstance(pairs, list), "Results should be a JSON list."
    found = {}
    previous = float("inf")

    for item in pairs:
        assert isinstance(item, list) and len(item) == 3, f"Each item must be a list of length 3, got: {item}"
        idx1, idx2, score = item
        assert isinstance(idx1, int) and not isinstance(idx1, bool), "First two elements must be integers."
        assert isinstance(idx2, int) and not isinstance(idx2, bool), "First two elements must be integers."
        assert isinstance(score, (float, int)) and not isinstance(score, bool), "Third element must be numeric."
        assert isinstance(score, float), "Third element must be a float."
        assert 0 <= idx1 < len(documents) and 0 <= idx2 < len(documents), "Document index is out of range."
        assert idx1 < idx2, "Each deduplicated pair must keep the smaller index first."
        assert math.isfinite(score), "Similarity must be finite."
        assert score <= previous, "Results are not sorted by similarity score in descending order."
        previous = score
        assert score >= 0.80, f"Similarity {score} is less than 0.80"
        assert score <= 1.0001, f"Similarity {score} is greater than expected bounds"
        key = (idx1, idx2)
        assert key not in found, f"Duplicate pair found: {key}"
        found[key] = score

    assert set(found) == set(expected), f"Incorrect pairs: expected {set(expected)}, got {set(found)}"
    for key, wanted_score in expected.items():
        assert found[key] == pytest.approx(wanted_score, abs=1e-12), \
            f"Incorrect rounded similarity for {key}: expected {wanted_score}, got {found[key]}"


def execute_and_validate(documents):
    corpus_before = open(CORPUS_FILE, "rb").read()
    if os.path.lexists(RESULTS_FILE):
        os.unlink(RESULTS_FILE)
    result = subprocess.run(
        [sys.executable, COMPUTE_SCRIPT],
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, \
        f"compute_retrieval.py failed:\n{result.stdout}\n{result.stderr}"
    assert open(CORPUS_FILE, "rb").read() == corpus_before, "compute_retrieval.py modified corpus.json"
    validate_results(documents, expected_pairs(documents))


def random_token():
    return "tok" + "".join(secrets.choice(string.ascii_lowercase) for _ in range(14))


def make_challenge_corpus():
    exact = [random_token() for _ in range(6)]
    shared = [random_token() for _ in range(8)]
    return [
        " ".join(exact),
        " ".join(exact),
        " ".join(shared + [random_token()]),
        " ".join(shared + [random_token()]),
        " ".join(random_token() for _ in range(7)),
        " ".join(random_token() for _ in range(7)),
        " ".join(random_token() for _ in range(7)),
    ]


def run_pytest(node):
    return subprocess.run(
        [sys.executable, "-m", "pytest", node],
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )


def test_scripts_exist():
    assert_regular_file(COMPUTE_SCRIPT)
    assert_regular_file(TEST_SCRIPT)
    assert_regular_file(CORPUS_FILE)


def test_results_file_exists_and_valid():
    original_corpus_bytes = open(CORPUS_FILE, "rb").read()
    original_documents = json.loads(original_corpus_bytes)
    assert isinstance(original_documents, list) and all(isinstance(d, str) for d in original_documents)
    assert len(original_documents) >= 2

    execute_and_validate(original_documents)
    original_results_bytes = open(RESULTS_FILE, "rb").read()

    challenge = make_challenge_corpus()
    challenge_expected = expected_pairs(challenge)
    assert len(challenge_expected) >= 2
    assert any(0.80 <= score < 0.9999 for score in challenge_expected.values())

    try:
        with open(CORPUS_FILE, "w", encoding="utf-8") as handle:
            json.dump(challenge, handle)
        execute_and_validate(challenge)
    finally:
        with open(CORPUS_FILE, "wb") as handle:
            handle.write(original_corpus_bytes)
        with open(RESULTS_FILE, "wb") as handle:
            handle.write(original_results_bytes)

    # Regenerate the required final artifact from the real corpus.
    execute_and_validate(original_documents)


def test_accuracy_script_passes():
    valid_results = open(RESULTS_FILE, "rb").read()
    try:
        result = run_pytest(TEST_SCRIPT)
        assert result.returncode == 0, \
            f"pytest {TEST_SCRIPT} failed with output:\n{result.stdout}\n{result.stderr}"

        for name in ("test_numerical_bounds", "test_schema"):
            node = f"{TEST_SCRIPT}::{name}"
            result = run_pytest(node)
            assert result.returncode == 0, \
                f"Required test {name} is missing or fails on valid output:\n{result.stdout}\n{result.stderr}"

        with open(RESULTS_FILE, "w", encoding="utf-8") as handle:
            json.dump([[0, 1, 1.1]], handle)
        result = run_pytest(f"{TEST_SCRIPT}::test_numerical_bounds")
        assert result.returncode != 0, "test_numerical_bounds did not reject an out-of-bounds score"

        with open(RESULTS_FILE, "w", encoding="utf-8") as handle:
            json.dump([[0, "1", 0.9]], handle)
        result = run_pytest(f"{TEST_SCRIPT}::test_schema")
        assert result.returncode != 0, "test_schema did not reject an invalid item schema"
    finally:
        with open(RESULTS_FILE, "wb") as handle:
            handle.write(valid_results)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
