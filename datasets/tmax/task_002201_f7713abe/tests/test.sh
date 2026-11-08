#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math

import librosa
import numpy as np
import pytest
import requests
from scipy import stats

BASE_URL = "http://127.0.0.1:8080"


def compute_reference():
    audio, sample_rate = librosa.load("/app/data.wav", sr=None, mono=True)
    chunk_count = len(audio) // sample_rate
    assert chunk_count >= 2

    embeddings = []
    for chunk_id in range(chunk_count):
        start = chunk_id * sample_rate
        chunk = audio[start:start + sample_rate]
        mfcc = librosa.feature.mfcc(y=chunk, sr=sample_rate, n_mfcc=13)
        embeddings.append(np.mean(mfcc, axis=1))
    embeddings = np.asarray(embeddings)

    split = (chunk_count + 1) // 2
    group_a = embeddings[:split, 0]
    group_b = embeddings[split:, 0]
    test_result = stats.ttest_ind(group_a, group_b, equal_var=False)

    mean_difference = float(np.mean(group_a) - np.mean(group_b))
    variance_a = float(np.var(group_a, ddof=1))
    variance_b = float(np.var(group_b, ddof=1))
    se_squared = variance_a / len(group_a) + variance_b / len(group_b)
    standard_error = math.sqrt(se_squared)
    denominator = ((variance_a / len(group_a)) ** 2 / (len(group_a) - 1) +
                   (variance_b / len(group_b)) ** 2 / (len(group_b) - 1))
    degrees_freedom = se_squared ** 2 / denominator
    margin = float(stats.t.ppf(0.975, degrees_freedom) * standard_error)

    expected_stats = {
        "t_stat": float(test_result.statistic),
        "p_value": float(test_result.pvalue),
        "ci_lower": mean_difference - margin,
        "ci_upper": mean_difference + margin,
    }
    return embeddings, expected_stats


EMBEDDINGS, EXPECTED_STATS = compute_reference()


def request_retrieval(chunk_id, top_k):
    try:
        response = requests.post(
            f"{BASE_URL}/retrieve",
            json={"chunk_id": chunk_id, "top_k": top_k},
            timeout=5,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the /retrieve endpoint: {exc}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response from /retrieve is not valid JSON")

    assert "similar_chunks" in data, "Missing 'similar_chunks' key in /retrieve response"
    similar_chunks = data["similar_chunks"]
    assert isinstance(similar_chunks, list), "similar_chunks must be a list"
    assert len(similar_chunks) == top_k, f"Expected {top_k} similar chunks, got {len(similar_chunks)}"
    return similar_chunks


def assert_correct_retrieval(chunk_id, top_k, returned):
    chunk_count = len(EMBEDDINGS)
    assert all(isinstance(item, int) and not isinstance(item, bool) for item in returned)
    assert len(set(returned)) == len(returned), "Retrieved chunk IDs must be unique"
    assert chunk_id not in returned, "The queried chunk must be excluded"
    assert all(0 <= item < chunk_count for item in returned), "Returned an invalid chunk ID"

    distances = np.linalg.norm(EMBEDDINGS - EMBEDDINGS[chunk_id], axis=1)
    available = [item for item in range(chunk_count) if item != chunk_id]

    # Results must be in nondecreasing distance order. Very small tolerance permits
    # arbitrary ordering only for chunks whose computed distances are effectively tied.
    for left, right in zip(returned, returned[1:]):
        assert distances[left] <= distances[right] + 1e-4 + 1e-6 * abs(distances[right]), \
            "similar_chunks is not sorted by Euclidean distance"

    unselected = [item for item in available if item not in returned]
    if unselected:
        largest_selected = max(float(distances[item]) for item in returned)
        smallest_unselected = min(float(distances[item]) for item in unselected)
        assert largest_selected <= smallest_unselected + 1e-4 + 1e-6 * abs(smallest_unselected), \
            "The response did not contain the top_k nearest embeddings"


def test_stats_endpoint():
    try:
        response = requests.get(f"{BASE_URL}/stats", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the /stats endpoint: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response from /stats is not valid JSON")

    expected_keys = {"t_stat", "p_value", "ci_lower", "ci_upper"}
    assert expected_keys.issubset(data.keys()), f"Missing keys in /stats response. Expected {expected_keys}, got {set(data.keys())}"

    assert isinstance(data["t_stat"], (int, float)), "t_stat must be a number"
    assert isinstance(data["p_value"], (int, float)), "p_value must be a number"
    assert isinstance(data["ci_lower"], (int, float)), "ci_lower must be a number"
    assert isinstance(data["ci_upper"], (int, float)), "ci_upper must be a number"

    ci_lower = data["ci_lower"]
    ci_upper = data["ci_upper"]
    assert (ci_lower > 0 and ci_upper > 0) or (ci_lower < 0 and ci_upper < 0), "Confidence interval should not contain 0"

    assert np.isclose(data["t_stat"], EXPECTED_STATS["t_stat"], rtol=2e-4, atol=1e-3), \
        f"Incorrect Welch t-statistic: expected {EXPECTED_STATS['t_stat']}, got {data['t_stat']}"
    assert np.isclose(data["p_value"], EXPECTED_STATS["p_value"], rtol=2e-4, atol=1e-10), \
        f"Incorrect p-value: expected {EXPECTED_STATS['p_value']}, got {data['p_value']}"
    assert np.isclose(data["ci_lower"], EXPECTED_STATS["ci_lower"], rtol=2e-4, atol=1e-3), \
        f"Incorrect CI lower bound: expected {EXPECTED_STATS['ci_lower']}, got {data['ci_lower']}"
    assert np.isclose(data["ci_upper"], EXPECTED_STATS["ci_upper"], rtol=2e-4, atol=1e-3), \
        f"Incorrect CI upper bound: expected {EXPECTED_STATS['ci_upper']}, got {data['ci_upper']}"


def test_retrieve_endpoint_original_case():
    similar_chunks = request_retrieval(0, 3)
    assert len(similar_chunks) == 3, f"Expected 3 similar chunks, got {len(similar_chunks)}"

    valid_similar_set = {1, 2, 3, 4}
    for chunk in similar_chunks:
        assert chunk in valid_similar_set, f"Chunk {chunk} is not in the expected set of similar chunks {valid_similar_set}"

    assert_correct_retrieval(0, 3, similar_chunks)


@pytest.mark.parametrize(
    "chunk_id,top_k",
    [(chunk_id, top_k) for chunk_id in range(len(EMBEDDINGS)) for top_k in (1, 3, len(EMBEDDINGS) - 1)],
)
def test_retrieve_matches_audio_embeddings(chunk_id, top_k):
    similar_chunks = request_retrieval(chunk_id, top_k)
    assert_correct_retrieval(chunk_id, top_k, similar_chunks)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
