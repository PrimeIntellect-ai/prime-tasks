#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import secrets
import subprocess
import pytest
import numpy as np

SCRIPT_PATH = "/home/user/scripts/evaluate_stability.py"
CORPUS_PATH = "/home/user/data/corpus.txt"
METRICS_PATH = "/home/user/artifacts/run_metrics.json"


def run_submission():
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"evaluate_stability.py exited with status {result.returncode}. "
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )


def independently_compute_metrics(corpus_text):
    documents = [line.lower().split() for line in corpus_text.splitlines()]
    vocabulary = sorted({token for document in documents for token in document})
    token_to_row = {token: i for i, token in enumerate(vocabulary)}
    tdm = np.zeros((len(vocabulary), len(documents)), dtype=float)

    for column, document in enumerate(documents):
        for token in document:
            tdm[token_to_row[token], column] += 1

    original_top_sv = float(np.linalg.svd(tdm, compute_uv=False)[0])
    np.random.seed(42)
    bootstrap_values = []
    for _ in range(100):
        indices = np.random.choice(len(documents), size=len(documents), replace=True)
        sampled_tdm = tdm[:, indices]
        bootstrap_values.append(float(np.linalg.svd(sampled_tdm, compute_uv=False)[0]))

    bootstrap_values = np.asarray(bootstrap_values)
    return {
        "vocab_size": len(vocabulary),
        "original_top_sv": round(original_top_sv, 4),
        "bootstrap_mean_sv": round(float(np.mean(bootstrap_values)), 4),
        "ci_lower": round(float(np.percentile(bootstrap_values, 2.5)), 4),
        "ci_upper": round(float(np.percentile(bootstrap_values, 97.5)), 4),
    }


def test_artifacts_directory_exists():
    """Test that the artifacts directory was created."""
    assert os.path.isdir("/home/user/artifacts"), "The artifacts directory /home/user/artifacts does not exist."


def test_script_exists_and_executes_on_original_corpus():
    """Ensure the requested Python artifact exists and actually generates the metrics."""
    assert os.path.isfile(SCRIPT_PATH), f"The file {SCRIPT_PATH} was not found."
    if os.path.exists(METRICS_PATH):
        os.remove(METRICS_PATH)
    run_submission()
    assert os.path.isfile(METRICS_PATH), "The script did not generate run_metrics.json."


def test_run_metrics_json_exists():
    """Test that the run_metrics.json file was generated."""
    assert os.path.isfile("/home/user/artifacts/run_metrics.json"), "The file /home/user/artifacts/run_metrics.json was not found."


def test_run_metrics_schema_and_values():
    """Test that the run_metrics.json contains the correct schema and expected values."""
    metrics_path = "/home/user/artifacts/run_metrics.json"

    with open(metrics_path, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file run_metrics.json does not contain valid JSON.")

    expected_keys = {
        "vocab_size",
        "original_top_sv",
        "bootstrap_mean_sv",
        "ci_lower",
        "ci_upper"
    }

    assert set(metrics.keys()) == expected_keys, f"JSON keys do not match expected schema. Found: {list(metrics.keys())}"

    # Check types
    assert isinstance(metrics["vocab_size"], int), "vocab_size must be an integer."
    assert isinstance(metrics["original_top_sv"], float), "original_top_sv must be a float."
    assert isinstance(metrics["bootstrap_mean_sv"], float), "bootstrap_mean_sv must be a float."
    assert isinstance(metrics["ci_lower"], float), "ci_lower must be a float."
    assert isinstance(metrics["ci_upper"], float), "ci_upper must be a float."

    # Check values with a small tolerance for floating point and SVD solver differences
    assert metrics["vocab_size"] == 22, f"Expected vocab_size 22, got {metrics['vocab_size']}"

    # Check original_top_sv
    assert abs(metrics["original_top_sv"] - 4.1485) <= 0.001, \
        f"Expected original_top_sv around 4.1485, got {metrics['original_top_sv']}"

    # Check bootstrap_mean_sv
    assert abs(metrics["bootstrap_mean_sv"] - 4.3989) <= 0.001, \
        f"Expected bootstrap_mean_sv around 4.3989, got {metrics['bootstrap_mean_sv']}"

    # Check ci_lower
    assert abs(metrics["ci_lower"] - 3.0315) <= 0.001, \
        f"Expected ci_lower around 3.0315, got {metrics['ci_lower']}"

    # Check ci_upper
    assert abs(metrics["ci_upper"] - 5.8606) <= 0.001, \
        f"Expected ci_upper around 5.8606, got {metrics['ci_upper']}"

    # Check if values are properly rounded to 4 decimal places
    for key in ["original_top_sv", "bootstrap_mean_sv", "ci_lower", "ci_upper"]:
        val_str = str(metrics[key])
        if "." in val_str:
            decimals = len(val_str.split(".")[1])
            assert decimals <= 4, f"Value for {key} ({metrics[key]}) is not rounded to 4 decimal places."


def test_script_computes_metrics_for_unseen_corpus():
    """Exercise the implementation on a randomized corpus and independently derive its answers."""
    rng = secrets.SystemRandom()
    document_count = rng.randint(4, 9)
    vocabulary_size = rng.randint(5, 13)
    tokens = ["t" + secrets.token_hex(6) for _ in range(vocabulary_size)]
    counts = [[rng.randint(0, 4) for _ in range(document_count)] for _ in range(vocabulary_size)]

    # Ensure every generated vocabulary token occurs and every document is nonempty.
    for row in range(vocabulary_size):
        if not any(counts[row]):
            counts[row][rng.randrange(document_count)] = rng.randint(1, 4)
    for column in range(document_count):
        if not any(counts[row][column] for row in range(vocabulary_size)):
            counts[rng.randrange(vocabulary_size)][column] = rng.randint(1, 4)

    lines = []
    for column in range(document_count):
        words = []
        for row, token in enumerate(tokens):
            words.extend([token] * counts[row][column])
        rng.shuffle(words)
        lines.append(" ".join(words))
    randomized_corpus = "\n".join(lines) + "\n"
    expected = independently_compute_metrics(randomized_corpus)

    with open(CORPUS_PATH, "r") as f:
        original_corpus = f.read()

    try:
        with open(CORPUS_PATH, "w") as f:
            f.write(randomized_corpus)
        if os.path.exists(METRICS_PATH):
            os.remove(METRICS_PATH)
        run_submission()
        assert os.path.isfile(METRICS_PATH), "The script did not generate metrics for the test corpus."
        with open(METRICS_PATH, "r") as f:
            actual = json.load(f)

        assert set(actual.keys()) == set(expected.keys()), "Generated JSON has an incorrect schema."
        assert isinstance(actual["vocab_size"], int), "vocab_size must be an integer."
        for key in ["original_top_sv", "bootstrap_mean_sv", "ci_lower", "ci_upper"]:
            assert isinstance(actual[key], float), f"{key} must be a float."
        assert actual["vocab_size"] == expected["vocab_size"]
        for key in ["original_top_sv", "bootstrap_mean_sv", "ci_lower", "ci_upper"]:
            assert abs(actual[key] - expected[key]) <= 0.0001, (
                f"Incorrect {key} for randomized corpus: expected {expected[key]}, got {actual[key]}"
            )
    finally:
        with open(CORPUS_PATH, "w") as f:
            f.write(original_corpus)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
