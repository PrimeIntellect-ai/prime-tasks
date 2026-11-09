#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import re
import numpy as np
import pytest

def compute_expected_mean_similarity():
    raw_data_dir = '/home/user/raw_data'
    files = sorted(os.listdir(raw_data_dir))
    docs = []
    vocab = set()
    for f in files:
        with open(os.path.join(raw_data_dir, f), 'r') as file:
            text = file.read().lower()
            for p in ['.', ',', '!', '?']:
                text = text.replace(p, '')
            tokens = text.split()
            docs.append(tokens)
            vocab.update(tokens)

    vocab = sorted(list(vocab))
    vocab_idx = {w: i for i, w in enumerate(vocab)}

    # Vectorize
    TF = [[0] * len(vocab) for _ in range(len(docs))]
    for i, tokens in enumerate(docs):
        for token in tokens:
            TF[i][vocab_idx[token]] += 1

    # Cosine similarity
    norms = []
    for row in TF:
        norm = math.sqrt(sum(x * x for x in row))
        norms.append(norm if norm > 0 else 1.0)

    TF_norm = []
    for i, row in enumerate(TF):
        TF_norm.append([x / norms[i] for x in row])

    pairwise_sims = []
    for i in range(len(docs)):
        for j in range(i + 1, len(docs)):
            sim = sum(TF_norm[i][k] * TF_norm[j][k] for k in range(len(vocab)))
            pairwise_sims.append(sim)

    mean_sim = sum(pairwise_sims) / len(pairwise_sims)
    return round(mean_sim, 4)

def compute_expected_bootstrap_results():
    raw_data_dir = '/home/user/raw_data'
    files = sorted(os.listdir(raw_data_dir))
    docs = []
    vocab = set()

    for filename in files:
        with open(os.path.join(raw_data_dir, filename), 'r') as file:
            text = file.read().lower()
        for punctuation in ['.', ',', '!', '?']:
            text = text.replace(punctuation, '')
        tokens = text.split()
        docs.append(tokens)
        vocab.update(tokens)

    vocabulary = sorted(vocab)
    vocab_idx = {term: index for index, term in enumerate(vocabulary)}
    tf = np.zeros((len(docs), len(vocabulary)), dtype=float)
    for doc_index, tokens in enumerate(docs):
        for token in tokens:
            tf[doc_index, vocab_idx[token]] += 1

    norms = np.linalg.norm(tf, axis=1)
    normalized = np.zeros_like(tf)
    nonzero = norms != 0
    normalized[nonzero] = tf[nonzero] / norms[nonzero, None]
    similarity_matrix = normalized @ normalized.T
    pairwise_sims = similarity_matrix[np.triu_indices(len(docs), k=1)]

    np.random.seed(42)
    bootstrap_means = []
    for _ in range(1000):
        sample = np.random.choice(
            pairwise_sims, size=len(pairwise_sims), replace=True
        )
        bootstrap_means.append(np.mean(sample))

    ci_lower, ci_upper = np.percentile(bootstrap_means, [2.5, 97.5])
    return (
        round(float(np.mean(pairwise_sims)), 4),
        round(float(ci_lower), 4),
        round(float(ci_upper), 4),
    )

def test_output_file_exists():
    output_path = '/home/user/etl_output.json'
    assert os.path.exists(output_path), f"Expected output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"{output_path} is not a file."

def test_output_file_content():
    output_path = '/home/user/etl_output.json'
    assert os.path.exists(output_path), "Output file missing."

    with open(output_path, 'r') as f:
        raw_content = f.read()

    try:
        data = json.loads(raw_content)
    except json.JSONDecodeError:
        pytest.fail(f"File {output_path} is not valid JSON.")

    expected_keys = {"mean_similarity", "ci_lower", "ci_upper"}
    assert set(data.keys()) == expected_keys, f"JSON keys do not match expected. Found {list(data.keys())}, expected {list(expected_keys)}"

    for key in expected_keys:
        assert isinstance(data[key], float), f"Value for {key} should be a float, got {type(data[key])}."
        pattern = rf'"{re.escape(key)}"\s*:\s*-?(?:0|[1-9]\d*)\.\d{{4}}(?=\s*[,}}])'
        assert re.search(pattern, raw_content), f"Value for {key} must be formatted with exactly 4 decimal places."

    expected_mean = compute_expected_mean_similarity()
    assert math.isclose(data["mean_similarity"], expected_mean, rel_tol=1e-4), \
        f"mean_similarity is incorrect. Expected ~{expected_mean}, got {data['mean_similarity']}."

    expected_np_mean, expected_lower, expected_upper = compute_expected_bootstrap_results()
    assert data["mean_similarity"] == expected_np_mean, \
        f"mean_similarity is incorrect. Expected {expected_np_mean}, got {data['mean_similarity']}."
    assert data["ci_lower"] == expected_lower, \
        f"ci_lower is incorrect. Expected {expected_lower}, got {data['ci_lower']}."
    assert data["ci_upper"] == expected_upper, \
        f"ci_upper is incorrect. Expected {expected_upper}, got {data['ci_upper']}."

    assert data["ci_lower"] <= data["mean_similarity"], "ci_lower should be less than or equal to mean_similarity."
    assert data["ci_upper"] >= data["mean_similarity"], "ci_upper should be greater than or equal to mean_similarity."
    assert data["ci_lower"] < data["ci_upper"], "ci_lower should be strictly less than ci_upper."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
