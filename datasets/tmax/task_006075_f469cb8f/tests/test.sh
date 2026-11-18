#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import string
import math
from scipy import stats

def tokenize(text):
    text = text.lower()
    for p in string.punctuation:
        text = text.replace(p, "")
    return text.split()

def get_embedding(tokens, embeddings):
    valid_embs = [embeddings[w] for w in tokens if w in embeddings]
    if not valid_embs:
        return [0.0] * 10
    n = len(valid_embs)
    dim = len(valid_embs[0])
    res = [0.0] * dim
    for e in valid_embs:
        for i in range(dim):
            res[i] += e[i]
    return [x / n for x in res]

def dot_product(v1, v2):
    return sum(x * y for x, y in zip(v1, v2))

def norm(v):
    return math.sqrt(sum(x * x for x in v))

def cosine_similarity(v1, v2):
    n1 = norm(v1)
    n2 = norm(v2)
    if n1 == 0 or n2 == 0:
        return 0.0
    return dot_product(v1, v2) / (n1 * n2)

def sample_variance(values):
    mean = sum(values) / len(values)
    return sum((x - mean) ** 2 for x in values) / (len(values) - 1)

def test_results_json():
    results_path = '/home/user/results.json'
    assert os.path.isfile(results_path), f"File {results_path} is missing."

    with open(results_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{results_path} is not valid JSON."

    expected_keys = {"top_3_datasets", "mean_diff", "p_value", "ci_lower", "ci_upper"}
    assert set(results.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}."

    # Recompute deterministic parts
    with open('/home/user/word_embeddings.json', 'r') as f:
        embeddings = json.load(f)

    with open('/home/user/query.txt', 'r') as f:
        query_text = f.read()

    query_tokens = tokenize(query_text)
    query_emb = get_embedding(query_tokens, embeddings)

    dataset_sims = {}
    for i in range(1, 21):
        fname = f"dataset_{i}.txt"
        with open(f'/home/user/datasets/{fname}', 'r') as f:
            text = f.read()
        tokens = tokenize(text)
        emb = get_embedding(tokens, embeddings)
        sim = cosine_similarity(query_emb, emb)
        dataset_sims[fname] = sim

    sorted_datasets = sorted(dataset_sims.keys(), key=lambda k: dataset_sims[k], reverse=True)
    expected_top_3 = sorted_datasets[:3]

    assert results["top_3_datasets"] == expected_top_3, f"Expected top_3_datasets to be {expected_top_3}, got {results['top_3_datasets']}"

    with open('/home/user/subset.txt', 'r') as f:
        subset = set(f.read().splitlines())

    group_a = [dataset_sims[k] for k in dataset_sims if k in subset]
    group_b = [dataset_sims[k] for k in dataset_sims if k not in subset]

    mean_a = sum(group_a) / len(group_a)
    mean_b = sum(group_b) / len(group_b)
    expected_mean_diff = mean_a - mean_b

    assert math.isclose(results["mean_diff"], expected_mean_diff, abs_tol=1e-4), f"Expected mean_diff around {expected_mean_diff:.5f}, got {results['mean_diff']}"

    assert isinstance(results["p_value"], float), "p_value must be a float"
    assert isinstance(results["ci_lower"], float), "ci_lower must be a float"
    assert isinstance(results["ci_upper"], float), "ci_upper must be a float"
    assert results["ci_lower"] <= results["ci_upper"], "ci_lower should be <= ci_upper"

    # Recompute the required two-sided Welch t-test and Satterthwaite CI.
    expected_p_value = float(stats.ttest_ind(group_a, group_b, equal_var=False).pvalue)

    n_a = len(group_a)
    n_b = len(group_b)
    var_a = sample_variance(group_a)
    var_b = sample_variance(group_b)
    term_a = var_a / n_a
    term_b = var_b / n_b
    standard_error = math.sqrt(term_a + term_b)
    degrees_freedom = ((term_a + term_b) ** 2) / (
        (term_a ** 2) / (n_a - 1) + (term_b ** 2) / (n_b - 1)
    )
    critical_t = float(stats.t.ppf(0.975, degrees_freedom))
    expected_ci_lower = expected_mean_diff - critical_t * standard_error
    expected_ci_upper = expected_mean_diff + critical_t * standard_error

    assert math.isclose(results["p_value"], round(expected_p_value, 5), rel_tol=0.0, abs_tol=5e-6), \
        f"Expected p_value {expected_p_value:.5f}, got {results['p_value']}"
    assert math.isclose(results["ci_lower"], round(expected_ci_lower, 5), rel_tol=0.0, abs_tol=5e-6), \
        f"Expected ci_lower {expected_ci_lower:.5f}, got {results['ci_lower']}"
    assert math.isclose(results["ci_upper"], round(expected_ci_upper, 5), rel_tol=0.0, abs_tol=5e-6), \
        f"Expected ci_upper {expected_ci_upper:.5f}, got {results['ci_upper']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
