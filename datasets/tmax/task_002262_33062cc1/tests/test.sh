#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
from pathlib import Path

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
import pytest
from sklearn.decomposition import PCA
from sklearn.datasets import make_classification

SCRIPT_PATH = Path('/home/user/etl_diagnostic.py')
DATA_PATH = Path('/home/user/data.parquet')
PLOT_PATH = Path('/home/user/pca_plot.png')
JSON_PATH = Path('/home/user/tracking.json')


def expected_result(df):
    sample_df = df.sample(n=1000, replace=True, random_state=42)
    pca = PCA()
    pca.fit(sample_df)
    cumulative = pca.explained_variance_ratio_.cumsum()
    n_components = int(np.flatnonzero(cumulative >= 0.85)[0] + 1)
    return n_components, float(cumulative[n_components - 1])


def run_script():
    PLOT_PATH.unlink(missing_ok=True)
    JSON_PATH.unlink(missing_ok=True)
    completed = subprocess.run(
        ['python3', str(SCRIPT_PATH)],
        text=True,
        capture_output=True,
        timeout=120,
        env={**os.environ, 'MPLBACKEND': 'Agg'},
    )
    assert completed.returncode == 0, (
        f'etl_diagnostic.py failed with exit code {completed.returncode}.\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )


def assert_generated_outputs(df):
    expected_n, expected_variance = expected_result(df)

    assert JSON_PATH.is_file(), f'Expected tracking file at {JSON_PATH} is missing.'
    with JSON_PATH.open() as f:
        result = json.load(f)
    assert result.get('n_components') == expected_n, (
        f"Expected minimum n_components={expected_n}, got {result.get('n_components')}."
    )
    assert isinstance(result.get('variance_explained'), float)
    assert result['variance_explained'] == pytest.approx(expected_variance, abs=1e-12, rel=1e-12), (
        'tracking.json does not contain the exact cumulative variance produced by '
        'PCA on the required bootstrap sample.'
    )

    assert PLOT_PATH.is_file(), f'Expected plot file at {PLOT_PATH} is missing.'
    assert PLOT_PATH.stat().st_size > 0, f'Plot file at {PLOT_PATH} is empty.'
    assert PLOT_PATH.read_bytes()[:8] == b'\x89PNG\r\n\x1a\n', 'pca_plot.png is not a PNG file.'
    image = mpimg.imread(PLOT_PATH)
    assert image.ndim in (2, 3) and image.shape[0] > 1 and image.shape[1] > 1
    assert np.ptp(image.astype(float)) > 0, 'pca_plot.png appears to be blank.'


def test_script_executes_and_computes_bootstrap_pca():
    assert SCRIPT_PATH.is_file(), f'Expected diagnostic script at {SCRIPT_PATH} is missing.'
    assert DATA_PATH.is_file(), f'Expected data file at {DATA_PATH} is missing.'

    original_bytes = DATA_PATH.read_bytes()
    original_df = pd.read_parquet(DATA_PATH)

    # Confirm the task's supplied data was not replaced or altered.
    expected_x, _ = make_classification(
        n_samples=5000,
        n_features=50,
        n_informative=15,
        n_redundant=10,
        random_state=123,
    )
    assert list(original_df.columns) == [f'feat_{i}' for i in range(50)]
    assert original_df.shape == expected_x.shape
    assert np.array_equal(original_df.to_numpy(), expected_x), 'data.parquet was modified.'

    # Execute against the supplied data and verify the independently recomputed answer.
    run_script()
    assert DATA_PATH.read_bytes() == original_bytes, 'The script modified data.parquet.'
    assert_generated_outputs(original_df)

    # Exercise the implementation on an additional verifier-created data set so that
    # hard-coded tracking values cannot pass. Restore the supplied data and its final
    # outputs before this test returns.
    rng = np.random.RandomState(9173)
    latent = rng.normal(size=(1400, 12))
    latent[:, 3] = 0.8 * latent[:, 0] + 0.2 * rng.normal(size=1400)
    latent[:, 7] = 0.5 * latent[:, 1] - 0.4 * latent[:, 2] + 0.1 * rng.normal(size=1400)
    latent *= np.array([8.0, 5.0, 3.0, 2.0, 1.5, 1.0, 0.8, 0.5, 0.3, 0.2, 0.1, 0.05])
    challenge_df = pd.DataFrame(latent, columns=[f'challenge_{i}' for i in range(12)])

    try:
        challenge_df.to_parquet(DATA_PATH)
        challenge_bytes = DATA_PATH.read_bytes()
        run_script()
        assert DATA_PATH.read_bytes() == challenge_bytes, 'The script modified data.parquet.'
        assert_generated_outputs(challenge_df)
    finally:
        DATA_PATH.write_bytes(original_bytes)

    # Leave the required artifacts corresponding to the original supplied data.
    run_script()
    assert DATA_PATH.read_bytes() == original_bytes, 'The script modified data.parquet.'
    assert_generated_outputs(original_df)


def test_pca_plot_created():
    """Verify that the PCA plot image was created and is not empty."""
    plot_path = '/home/user/pca_plot.png'
    assert os.path.isfile(plot_path), f"Expected plot file at {plot_path} is missing."
    assert os.path.getsize(plot_path) > 0, f"Plot file at {plot_path} is empty."


def test_tracking_json_created_and_valid():
    """Verify that the tracking JSON file exists and contains the correct structure and invariants."""
    json_path = '/home/user/tracking.json'
    assert os.path.isfile(json_path), f"Expected tracking JSON file at {json_path} is missing."

    with open(json_path, 'r') as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File at {json_path} is not valid JSON.")

    assert "n_components" in result, "Key 'n_components' is missing from tracking.json."
    assert "variance_explained" in result, "Key 'variance_explained' is missing from tracking.json."

    n_comp = result["n_components"]
    var_expl = result["variance_explained"]

    assert isinstance(n_comp, int), f"'n_components' should be an integer, got {type(n_comp).__name__}."
    assert isinstance(var_expl, float), f"'variance_explained' should be a float, got {type(var_expl).__name__}."

    assert n_comp > 0, f"'n_components' must be strictly positive, got {n_comp}."
    assert var_expl >= 0.85, f"'variance_explained' must be >= 0.85, got {var_expl}."
    assert var_expl <= 1.0, f"'variance_explained' must be <= 1.0, got {var_expl}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
