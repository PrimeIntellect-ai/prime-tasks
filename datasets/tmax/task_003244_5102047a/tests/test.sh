#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import importlib.metadata
import importlib.util
import numpy as np
import scipy.stats as stats
import pytest


def _assert_cosine_implementation(cosine_sim, implementation_name):
    # Preserve the original orthogonal-vector check.
    try:
        res = cosine_sim(np.array([1.0, 0.0]), np.array([0.0, 1.0]))
        assert np.isclose(res, 0.0), "cosine_sim did not return expected result"
    except Exception as e:
        pytest.fail(f"{implementation_name}.cosine_sim failed or is still broken: {e}")

    # Exercise non-zero and verifier-generated cases so a constant implementation
    # cannot masquerade as a repaired cosine similarity function.
    cases = [
        (np.array([1.0, 0.0]), np.array([1.0, 0.0])),
        (np.array([1.0, 2.0]), np.array([3.0, -4.0])),
        (np.array([2.0, -1.0, 4.0]), np.array([-3.0, 5.0, 2.0])),
    ]
    rng = np.random.default_rng()
    for dim in (3, 17, 128):
        cases.append((rng.normal(size=dim), rng.normal(size=dim)))

    for a, b in cases:
        expected = np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))
        try:
            actual = cosine_sim(a, b)
        except Exception as e:
            pytest.fail(f"{implementation_name}.cosine_sim raised on valid vectors: {e}")
        actual_array = np.asarray(actual)
        assert actual_array.shape == (), f"{implementation_name}.cosine_sim must return a scalar"
        assert np.isfinite(actual_array), f"{implementation_name}.cosine_sim returned a non-finite value"
        assert np.isclose(actual, expected, rtol=1e-7, atol=1e-9), (
            f"{implementation_name}.cosine_sim returned {actual}, expected {expected}"
        )


def test_fastvecsearch_installed_and_fixed():
    try:
        import fastvecsearch
    except ImportError:
        pytest.fail("fastvecsearch package is not installed or importable.")

    try:
        importlib.metadata.version('fastvecsearch')
    except importlib.metadata.PackageNotFoundError:
        pytest.fail("fastvecsearch is importable but is not installed as a package.")

    assert hasattr(fastvecsearch, 'cosine_sim'), "fastvecsearch is missing 'cosine_sim'"
    _assert_cosine_implementation(fastvecsearch.cosine_sim, "installed fastvecsearch")

    # The instruction requires repairing the vendored package itself, not merely
    # installing an unrelated replacement implementation.
    source_path = '/app/fastvecsearch/fastvecsearch/distance.py'
    assert os.path.isfile(source_path), f"Vendored package source missing: {source_path}"
    spec = importlib.util.spec_from_file_location('_vendored_fastvecsearch_distance', source_path)
    assert spec is not None and spec.loader is not None, "Could not load vendored fastvecsearch source"
    vendored_distance = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(vendored_distance)
    except Exception as e:
        pytest.fail(f"Vendored fastvecsearch source could not be executed: {e}")
    assert hasattr(vendored_distance, 'cosine_sim'), "Vendored package is missing 'cosine_sim'"
    _assert_cosine_implementation(vendored_distance.cosine_sim, "vendored fastvecsearch")


def test_hard_negatives_json_metrics():
    json_path = '/home/user/hard_negatives.json'
    assert os.path.exists(json_path), f"Output file missing: {json_path}"

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    assert "hard_negative_indices" in data, "Missing 'hard_negative_indices' in JSON"
    assert "ttest_p_value" in data, "Missing 'ttest_p_value' in JSON"
    assert "ci_lower" in data, "Missing 'ci_lower' in JSON"
    assert "ci_upper" in data, "Missing 'ci_upper' in JSON"

    agent_indices = np.array(data["hard_negative_indices"])
    assert agent_indices.shape == (500, 5), f"Expected 'hard_negative_indices' shape (500, 5), got {agent_indices.shape}"

    anchors_path = '/home/user/data/anchors.npy'
    candidates_path = '/home/user/data/candidates.npy'
    assert os.path.exists(anchors_path), f"Missing {anchors_path}"
    assert os.path.exists(candidates_path), f"Missing {candidates_path}"

    anchors = np.load(anchors_path)
    candidates = np.load(candidates_path)

    # Compute ground truth indices
    sims = anchors @ candidates.T
    gt_indices = np.argsort(-sims, axis=1)[:, :5]

    # Calculate overlap metric
    overlaps = []
    for i in range(500):
        overlaps.append(len(set(agent_indices[i]) & set(gt_indices[i])) / 5.0)
    mean_overlap = np.mean(overlaps)

    assert mean_overlap >= 0.98, f"Mean overlap too low. Expected >= 0.98, got {mean_overlap}"

    # Calculate ground truth stats
    np.random.seed(42)
    gt_hard_means = np.mean(np.take_along_axis(sims, gt_indices, axis=1), axis=1)
    random_indices = np.random.choice(candidates.shape[0], size=(500, 5))
    gt_rand_means = np.mean(np.take_along_axis(sims, random_indices, axis=1), axis=1)

    res = stats.ttest_rel(gt_hard_means, gt_rand_means)
    ci = res.confidence_interval(confidence_level=0.95)

    # Check metrics
    p_val_err = abs(data['ttest_p_value'] - res.pvalue)
    assert p_val_err <= 1e-4, f"p-value absolute error > 1e-4. Expected ~{res.pvalue}, got {data['ttest_p_value']} (err: {p_val_err})"

    ci_low_err = abs(data['ci_lower'] - ci.low)
    assert ci_low_err <= 1e-4, f"ci_lower absolute error > 1e-4. Expected ~{ci.low}, got {data['ci_lower']} (err: {ci_low_err})"

    ci_high_err = abs(data['ci_upper'] - ci.high)
    assert ci_high_err <= 1e-4, f"ci_upper absolute error > 1e-4. Expected ~{ci.high}, got {data['ci_upper']} (err: {ci_high_err})"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
