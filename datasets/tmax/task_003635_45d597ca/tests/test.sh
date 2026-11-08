#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest
import numpy as np
import pandas as pd

OUTPUT_PATH = '/home/user/pca_stability.json'
INPUT_PATH = '/home/user/sensor_data.csv'
FEATURES = [f's{i}' for i in range(1, 11)]


def test_pca_stability_json_exists():
    """Test that the output JSON file exists."""
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."


def test_pca_stability_json_structure_and_values():
    """Test the structure and invariants of the PCA stability JSON."""
    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} is not valid JSON.")

    expected_keys = {"mean_pc1_var", "ci_lower", "ci_upper"}
    assert set(result.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}, got {set(result.keys())}"

    mean_var = result["mean_pc1_var"]
    ci_lower = result["ci_lower"]
    ci_upper = result["ci_upper"]

    assert isinstance(mean_var, float), "mean_pc1_var must be a float"
    assert isinstance(ci_lower, float), "ci_lower must be a float"
    assert isinstance(ci_upper, float), "ci_upper must be a float"

    assert 0.0 <= mean_var <= 1.0, f"mean_pc1_var {mean_var} is out of bounds [0, 1]"
    assert 0.0 <= ci_lower <= 1.0, f"ci_lower {ci_lower} is out of bounds [0, 1]"
    assert 0.0 <= ci_upper <= 1.0, f"ci_upper {ci_upper} is out of bounds [0, 1]"

    assert ci_lower <= mean_var, f"ci_lower ({ci_lower}) should be <= mean_pc1_var ({mean_var})"
    assert mean_var <= ci_upper, f"mean_pc1_var ({mean_var}) should be <= ci_upper ({ci_upper})"


def test_results_match_bootstrap_pca_pipeline():
    """Independently recompute the required 500-iteration result."""
    assert os.path.isfile(INPUT_PATH), f"Input file {INPUT_PATH} is missing."
    source = pd.read_csv(INPUT_PATH)
    assert all(column in source.columns for column in FEATURES), "Input is missing required sensor columns."

    # Ensure the provided task input was not replaced with an easier dataset.
    rng = np.random.RandomState(123)
    base = rng.randn(300, 1)
    canonical_data = base * rng.randn(1, 10) + rng.randn(300, 10) * 0.5
    canonical = pd.DataFrame(canonical_data, columns=FEATURES)
    canonical.loc[12, 's3'] = 'ERROR'
    canonical.loc[45, 's7'] = 'NaN'
    canonical.loc[199, 's1'] = 'missing'
    canonical.loc[250, 's9'] = None

    observed_numeric = source[FEATURES].apply(pd.to_numeric, errors='coerce').to_numpy(dtype=float)
    canonical_numeric = canonical[FEATURES].apply(pd.to_numeric, errors='coerce').to_numpy(dtype=float)
    assert observed_numeric.shape == canonical_numeric.shape, "The supplied sensor dataset was modified."
    np.testing.assert_allclose(
        observed_numeric, canonical_numeric, rtol=1e-12, atol=1e-12,
        equal_nan=True, err_msg="The supplied sensor dataset was modified."
    )

    cleaned = source[FEATURES].apply(pd.to_numeric, errors='coerce').astype(float).dropna()
    assert len(cleaned) >= 2, "Not enough valid rows remain after schema enforcement."

    pc1_variances = []
    for i in range(500):
        sample = cleaned.sample(n=len(cleaned), replace=True, random_state=i)
        centered = sample - sample.mean(axis=0)
        covariance = np.cov(centered.to_numpy(dtype=float), rowvar=False)
        eigenvalues = np.linalg.eigvalsh(covariance)
        pc1_variances.append(float(eigenvalues[-1] / eigenvalues.sum()))

    expected = {
        'mean_pc1_var': round(float(np.mean(pc1_variances)), 4),
        'ci_lower': round(float(np.percentile(pc1_variances, 2.5)), 4),
        'ci_upper': round(float(np.percentile(pc1_variances, 97.5)), 4),
    }

    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        result = json.load(f)

    for key, expected_value in expected.items():
        assert result[key] == expected_value, (
            f"{key} is incorrect: expected {expected_value:.4f}, got {result[key]!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
