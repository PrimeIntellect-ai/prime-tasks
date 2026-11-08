#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
from pathlib import Path
import subprocess

import matplotlib.image as mpimg
import numpy as np
import pandas as pd

PIPELINE = Path('/home/user/pipeline.py')
DATA = Path('/home/user/data.csv')
METRICS = Path('/home/user/metrics.txt')
PLOT = Path('/home/user/output_plot.png')


def run_pipeline():
    assert PIPELINE.is_file(), f'Pipeline script not found: {PIPELINE}'
    assert not PIPELINE.is_symlink(), 'pipeline.py must be a regular script, not a symlink'

    METRICS.unlink(missing_ok=True)
    PLOT.unlink(missing_ok=True)

    env = os.environ.copy()
    env.pop('DISPLAY', None)
    env.pop('MPLBACKEND', None)
    result = subprocess.run(
        ['python3', str(PIPELINE)],
        cwd='/home/user',
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f'pipeline.py failed:\n{result.stdout}'


def assert_output_plot_exists_and_valid():
    """Check that the plot was generated and is a valid, nonblank PNG image."""
    path = '/home/user/output_plot.png'
    assert os.path.isfile(path), f'Output plot not found: {path}'

    with open(path, 'rb') as f:
        header = f.read(8)
    assert header == b'\x89PNG\r\n\x1a\n', 'output_plot.png is not a valid PNG file'

    image = mpimg.imread(path)
    assert image.ndim in (2, 3), 'output_plot.png could not be decoded as an image'
    assert image.shape[0] >= 100 and image.shape[1] >= 100, 'output_plot.png is unexpectedly small'
    assert np.isfinite(image).all(), 'output_plot.png contains invalid pixel values'
    assert float(np.max(image) - np.min(image)) > 0.05, 'output_plot.png is blank'


def read_metrics():
    path = '/home/user/metrics.txt'
    assert os.path.isfile(path), f'Metrics file not found: {path}'
    with open(path, 'r') as f:
        content = f.read().strip().split('\n')
    assert len(content) == 3, f'metrics.txt must have exactly 3 lines, found {len(content)}'
    return [line.strip() for line in content]


def assert_original_metrics_txt_content():
    """Retain the exact assertions for the supplied dataset."""
    content = read_metrics()
    expected_mean = 'Mean: 101.44'
    expected_ci = 'CI: 98.66-104.29'
    expected_pred = 'Prediction: 1.50'

    assert content[0] == expected_mean, f"Line 1 mismatch. Expected '{expected_mean}', got '{content[0]}'"
    assert content[1] == expected_ci, f"Line 2 mismatch. Expected '{expected_ci}', got '{content[1]}'"
    assert content[2] == expected_pred, f"Line 3 mismatch. Expected '{expected_pred}', got '{content[2]}'"


def expected_metrics(values):
    clean = np.asarray(values, dtype=float)
    clean = clean[~np.isnan(clean)]
    assert len(clean) > 1

    np.random.seed(42)
    means = []
    for _ in range(1000):
        sample = np.random.choice(clean, size=len(clean), replace=True)
        means.append(np.mean(sample))
    ci_lower, mean_val, ci_upper = np.percentile(means, [2.5, 50, 97.5])

    scaled_mean = (mean_val - np.mean(clean)) / np.std(clean)
    pred = 3.2 * scaled_mean + 1.5
    return [
        f'Mean: {mean_val:.2f}',
        f'CI: {ci_lower:.2f}-{ci_upper:.2f}',
        f'Prediction: {pred:.2f}',
    ]


def test_pipeline_executes_and_computes_outputs():
    original_data = DATA.read_bytes()
    try:
        # First execute against the supplied dataset and retain all original checks.
        run_pipeline()
        assert_output_plot_exists_and_valid()
        assert_original_metrics_txt_content()
        plot_hashes = {hashlib.sha256(PLOT.read_bytes()).digest()}

        # Exercise the implementation on unpredictable datasets so fixed metric text
        # and a static image cannot satisfy the verifier.
        seed = int.from_bytes(os.urandom(16), 'little')
        rng = np.random.default_rng(seed)
        datasets = []

        values1 = rng.lognormal(mean=4.0, sigma=0.8, size=23)
        values1[[2, 11, 19]] = np.nan
        datasets.append(values1)

        values2 = np.concatenate([
            rng.normal(-35.0, 4.0, size=9),
            rng.normal(80.0, 13.0, size=12),
        ])
        rng.shuffle(values2)
        values2[[1, 7]] = np.nan
        datasets.append(values2)

        for values in datasets:
            pd.DataFrame({'value': values}).to_csv(DATA, index=False)
            expected = expected_metrics(values)
            run_pipeline()
            assert_output_plot_exists_and_valid()
            actual = read_metrics()
            assert actual == expected, f'Computed metrics mismatch. Expected {expected}, got {actual}'

            digest = hashlib.sha256(PLOT.read_bytes()).digest()
            assert digest not in plot_hashes, 'The plot did not change when the input dataset changed'
            plot_hashes.add(digest)

        # Leave outputs corresponding to the original requested dataset.
        DATA.write_bytes(original_data)
        run_pipeline()
        assert_output_plot_exists_and_valid()
        assert_original_metrics_txt_content()
    finally:
        DATA.write_bytes(original_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
