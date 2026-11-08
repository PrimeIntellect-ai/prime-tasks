#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import itertools
import re
from collections import Counter

import numpy as np
import pytest
from scipy.stats import ttest_ind

RESULTS_PATH = '/home/user/results.json'
CSV_PATH = '/home/user/abstracts.csv'
EXPECTED_KEYS = {
    'vocabulary_size',
    'pc1_mean_physics',
    'pc1_mean_biology',
    'ttest_p_value',
    'bootstrap_ci_lower',
    'bootstrap_ci_upper',
}
FLOAT_KEYS = EXPECTED_KEYS - {'vocabulary_size'}


def load_results():
    with open(RESULTS_PATH, 'r', encoding='utf-8') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f'File {RESULTS_PATH} is not valid JSON: {exc}')


def load_rows():
    assert os.path.exists(CSV_PATH), f'Dataset {CSV_PATH} is missing.'
    with open(CSV_PATH, 'r', encoding='utf-8', newline='') as f:
        return list(csv.DictReader(f))


def tokenize(text):
    cleaned = re.sub(r'[^a-z0-9 ]', '', text.lower())
    return [token for token in cleaned.split(' ') if token]


def candidate_vocabularies(rows):
    counts = Counter()
    tokenized = []
    for row in rows:
        tokens = tokenize(row['text'])
        tokenized.append(tokens)
        counts.update(tokens)

    assert len(counts) >= 50, 'Dataset does not contain 50 distinct tokens.'
    frequencies = sorted(counts.values(), reverse=True)
    cutoff = frequencies[49]
    required = sorted(token for token, count in counts.items() if count > cutoff)
    tied = sorted(token for token, count in counts.items() if count == cutoff)
    slots = 50 - len(required)

    # The instruction permits arbitrary tie resolution at the cutoff. Enumerate
    # every permitted vocabulary for this dataset rather than imposing one.
    combinations = math.comb(len(tied), slots)
    assert combinations <= 10000, 'Too many tied cutoff vocabularies to verify safely.'
    for selected in itertools.combinations(tied, slots):
        yield tokenized, required + list(selected)


def expected_pca_values(rows, tokenized, vocabulary):
    index = {token: i for i, token in enumerate(vocabulary)}
    matrix = np.zeros((len(rows), 50), dtype=float)
    for row_index, tokens in enumerate(tokenized):
        row_counts = Counter(tokens)
        for token, count in row_counts.items():
            column = index.get(token)
            if column is not None:
                matrix[row_index, column] = count

    centered = matrix - matrix.mean(axis=0)
    u, singular_values, _ = np.linalg.svd(centered, full_matrices=False)
    scores = u[:, 0] * singular_values[0]

    categories = np.asarray([row['category'] for row in rows])
    physics = scores[categories == 'Physics']
    biology = scores[categories == 'Biology']
    assert len(physics) >= 2 and len(biology) >= 2

    physics_mean = float(np.mean(physics))
    biology_mean = float(np.mean(biology))
    p_value = float(ttest_ind(physics, biology, equal_var=False).pvalue)
    return physics_mean, biology_mean, p_value


def exact_bootstrap_percentiles(rows):
    citations = [int(row['citations']) for row in rows if row['category'] == 'Biology']
    assert citations, 'Dataset has no Biology citations.'

    # Compute the exact distribution of a bootstrap sample sum. This avoids
    # requiring Python's RNG or a particular percentile interpolation rule.
    one_draw = np.bincount(citations).astype(float)
    one_draw /= one_draw.sum()
    sum_distribution = np.array([1.0])
    for _ in range(len(citations)):
        sum_distribution = np.convolve(sum_distribution, one_draw)
    cdf = np.cumsum(sum_distribution)
    lower_sum = int(np.searchsorted(cdf, 0.025, side='left'))
    upper_sum = int(np.searchsorted(cdf, 0.975, side='left'))
    return lower_sum / len(citations), upper_sum / len(citations)


def test_results_json_exists():
    assert os.path.exists(RESULTS_PATH), f'File {RESULTS_PATH} is missing.'
    assert os.path.isfile(RESULTS_PATH), f'Path {RESULTS_PATH} is not a file.'


def test_results_json_format_and_computations():
    results = load_results()
    assert isinstance(results, dict), 'results.json must contain a JSON object.'
    assert set(results.keys()) == EXPECTED_KEYS, \
        f'JSON keys do not match expected keys. Got {list(results.keys())}'
    assert results['vocabulary_size'] == 50, 'vocabulary_size must be exactly 50.'

    for key in EXPECTED_KEYS:
        value = results[key]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), \
            f'Value for {key} must be a number.'
        assert math.isfinite(float(value)), f'Value for {key} must be finite.'

    for key in FLOAT_KEYS:
        assert math.isclose(float(results[key]), round(float(results[key]), 4), abs_tol=1e-12), \
            f'Value for {key} must be rounded to 4 decimal places.'

    rows = load_rows()

    # Validate the complete tokenization -> DTM -> centering -> PCA/SVD ->
    # Welch-test pipeline. PC signs are mathematically arbitrary, so either
    # simultaneous sign orientation of the two group means is accepted.
    submitted_physics = float(results['pc1_mean_physics'])
    submitted_biology = float(results['pc1_mean_biology'])
    submitted_p = float(results['ttest_p_value'])
    matched = False
    expected_descriptions = []
    for tokenized, vocabulary in candidate_vocabularies(rows):
        physics_mean, biology_mean, p_value = expected_pca_values(rows, tokenized, vocabulary)
        expected_descriptions.append((physics_mean, biology_mean, p_value))
        p_matches = math.isclose(submitted_p, round(p_value, 4), abs_tol=1e-4)
        positive_sign = (
            math.isclose(submitted_physics, round(physics_mean, 4), abs_tol=1e-4)
            and math.isclose(submitted_biology, round(biology_mean, 4), abs_tol=1e-4)
        )
        negative_sign = (
            math.isclose(submitted_physics, round(-physics_mean, 4), abs_tol=1e-4)
            and math.isclose(submitted_biology, round(-biology_mean, 4), abs_tol=1e-4)
        )
        if p_matches and (positive_sign or negative_sign):
            matched = True
            break

    assert matched, (
        'PC1 category means and/or Welch p-value do not match the required '
        f'analysis. Computed possibilities: {expected_descriptions}'
    )

    # A 10,000-resample percentile estimate can differ slightly across valid
    # seeded RNG implementations and percentile interpolation conventions.
    # Compare it with the exact bootstrap distribution using a narrow tolerance
    # that accommodates that Monte Carlo variation without accepting guesses.
    expected_lower, expected_upper = exact_bootstrap_percentiles(rows)
    assert math.isclose(float(results['bootstrap_ci_lower']), expected_lower, abs_tol=0.06), \
        f'bootstrap_ci_lower expected near {expected_lower:.4f}, got {results["bootstrap_ci_lower"]}'
    assert math.isclose(float(results['bootstrap_ci_upper']), expected_upper, abs_tol=0.06), \
        f'bootstrap_ci_upper expected near {expected_upper:.4f}, got {results["bootstrap_ci_upper"]}'
    assert results['bootstrap_ci_lower'] <= results['bootstrap_ci_upper'], \
        'Bootstrap confidence interval endpoints are reversed.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
