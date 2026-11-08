#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
from functools import lru_cache

import numpy as np
import pandas as pd
import pytest

RESULT_FILE = '/home/user/ci_results.json'
DATA_FILE = '/home/user/experiment.csv'


def test_result_file_exists():
    """Test that the expected JSON output file exists."""
    assert os.path.isfile(RESULT_FILE), f"Expected result file not found at {RESULT_FILE}"


@lru_cache(maxsize=1)
def recompute_bootstrap_summary():
    """Load the supplied dataset and independently perform the requested bootstrap."""
    assert os.path.isfile(DATA_FILE), f"Expected dataset not found at {DATA_FILE}"
    df = pd.read_csv(DATA_FILE)
    assert list(df.columns) == ['x1', 'x2', 'x3', 'y'], "Dataset columns were changed"
    assert len(df) == 200, "Dataset row count was changed"

    # Ensure verification is performed against the original experiment rather than
    # an agent-modified dataset chosen to make arbitrary output pass.
    source_rng = np.random.RandomState(42)
    expected_x1 = source_rng.normal(0, 1, 200)
    expected_x2 = 2.0 * expected_x1 + source_rng.normal(0, 0.1, 200)
    expected_x3 = -1.5 * expected_x1 + source_rng.normal(0, 0.1, 200)
    expected_y = (
        expected_x1 + 0.5 * expected_x2 - 0.5 * expected_x3
        + source_rng.normal(0, 0.5, 200)
    )
    expected = np.column_stack((expected_x1, expected_x2, expected_x3, expected_y))
    np.testing.assert_allclose(
        df[['x1', 'x2', 'x3', 'y']].to_numpy(dtype=float),
        expected,
        rtol=1e-12,
        atol=1e-12,
        err_msg="The experiment dataset was modified",
    )

    X = df[['x1', 'x2', 'x3']].to_numpy(dtype=float)
    y = df['y'].to_numpy(dtype=float)
    n = len(df)
    alpha = 2.0
    identity = np.eye(X.shape[1])
    rng = np.random.default_rng(20260912)
    x1_coefficients = np.empty(10000, dtype=float)

    # With no intercept, Ridge is exactly (X.T X + alpha I)^-1 X.T y.
    for iteration in range(10000):
        indices = rng.integers(0, n, size=n)
        sample_x = X[indices]
        sample_y = y[indices]
        coefficient = np.linalg.solve(
            sample_x.T @ sample_x + alpha * identity,
            sample_x.T @ sample_y,
        )
        x1_coefficients[iteration] = coefficient[0]

    return {
        'mean': float(np.mean(x1_coefficients)),
        'lower_bound': float(np.percentile(x1_coefficients, 2.5)),
        'upper_bound': float(np.percentile(x1_coefficients, 97.5)),
    }


def test_result_file_format_and_values():
    """Test format, original bounds, and agreement with an independent bootstrap."""
    with open(RESULT_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULT_FILE} is not a valid JSON file.")

    expected_keys = {'mean', 'lower_bound', 'upper_bound'}
    actual_keys = set(data.keys())
    assert expected_keys.issubset(actual_keys), (
        f"JSON is missing expected keys. Found: {actual_keys}, Expected: {expected_keys}"
    )

    for key in expected_keys:
        assert isinstance(data[key], (int, float)), (
            f"Value for '{key}' must be a number, got {type(data[key])}"
        )

    mean = data['mean']
    lower = data['lower_bound']
    upper = data['upper_bound']

    # Preserve the original sanity assertions.
    assert 0.32 <= mean <= 0.36, f"Mean value {mean} is outside the expected range [0.32, 0.36]."
    assert 0.24 <= lower <= 0.29, f"Lower bound value {lower} is outside the expected range [0.24, 0.29]."
    assert 0.40 <= upper <= 0.44, f"Upper bound value {upper} is outside the expected range [0.40, 0.44]."

    assert lower < mean < upper, "Expected lower_bound < mean < upper_bound"

    reference = recompute_bootstrap_summary()
    # Allow normal Monte Carlo differences from use of another unprescribed RNG seed,
    # while rejecting values that merely fall somewhere in the old broad ranges.
    assert abs(mean - reference['mean']) <= 0.003, (
        f"Mean {mean} disagrees with independently recomputed bootstrap mean "
        f"{reference['mean']}"
    )
    assert abs(lower - reference['lower_bound']) <= 0.006, (
        f"Lower bound {lower} disagrees with independently recomputed bootstrap bound "
        f"{reference['lower_bound']}"
    )
    assert abs(upper - reference['upper_bound']) <= 0.006, (
        f"Upper bound {upper} disagrees with independently recomputed bootstrap bound "
        f"{reference['upper_bound']}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
