#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import sys

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
import pytest
from pandas.testing import assert_frame_equal
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import f1_score
from sklearn.model_selection import train_test_split
from sklearn.utils import resample

BASE = '/home/user/ml_pipeline'
SCRIPT = os.path.join(BASE, 'prepare_data.py')
RAW = os.path.join(BASE, 'raw_data.csv')
PLOT = os.path.join(BASE, 'correlation_plot.png')
PROCESSED = os.path.join(BASE, 'processed_data.csv')
METRICS = os.path.join(BASE, 'metrics.txt')


@pytest.fixture(scope='session', autouse=True)
def run_submission():
    assert os.path.isfile(SCRIPT), f'Expected Python script at {SCRIPT} is missing.'
    assert not os.path.islink(SCRIPT), 'prepare_data.py must be a real Python source file, not a symlink.'
    assert os.path.getsize(SCRIPT) > 0, 'prepare_data.py is empty.'

    for path in (PLOT, PROCESSED, METRICS):
        if os.path.lexists(path):
            os.remove(path)

    env = os.environ.copy()
    env['MPLBACKEND'] = 'Agg'
    result = subprocess.run(
        [sys.executable, SCRIPT], cwd=BASE, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=120
    )
    assert result.returncode == 0, f'prepare_data.py failed:\n{result.stdout}'


def sorted_rows(df):
    return df.sort_values(list(df.columns), kind='mergesort').reset_index(drop=True)


def expected_filtered_raw():
    raw = pd.read_csv(RAW)
    features = raw.drop(columns=['target'])
    corr = features.corr(method='pearson').abs()
    to_drop = []
    for later in range(len(features.columns)):
        for earlier in range(later):
            if corr.iloc[earlier, later] > 0.85:
                to_drop.append(features.columns[later])
                break
    return raw.drop(columns=to_drop)


def test_correlation_plot_generated():
    assert os.path.isfile(PLOT), f'Expected plot file at {PLOT} is missing.'

    file_size = os.path.getsize(PLOT)
    assert file_size > 5000, (
        f'Plot file {PLOT} is too small ({file_size} bytes), indicating it might still be blank.'
    )

    assert open(PLOT, 'rb').read(8) == b'\x89PNG\r\n\x1a\n', 'correlation_plot.png is not a PNG file.'
    image = mpimg.imread(PLOT)
    assert image.ndim in (2, 3) and image.shape[0] >= 200 and image.shape[1] >= 200, \
        f'Plot has invalid dimensions: {image.shape}'
    rgb = image[..., :3] if image.ndim == 3 else image
    assert np.isfinite(rgb).all(), 'Plot contains invalid pixel values.'
    assert float(np.std(rgb)) > 0.05, 'Plot is effectively blank or uniform.'
    quantized = np.round(rgb.reshape(-1, rgb.shape[-1] if rgb.ndim == 3 else 1) * 255).astype(np.uint8)
    assert len(np.unique(quantized, axis=0)) > 50, 'Plot lacks the color variation expected from a heatmap.'


def test_processed_data_csv():
    assert os.path.isfile(PROCESSED), f'Expected processed data file at {PROCESSED} is missing.'

    processed = pd.read_csv(PROCESSED)
    expected_columns = ['f1', 'f3', 'f4', 'target']
    assert list(processed.columns) == expected_columns, (
        f"Expected columns {expected_columns}, but got {list(processed.columns)}. 'f2' should be dropped."
    )
    assert len(processed) == 1800, (
        f'Expected 1800 rows in processed_data.csv, but got {len(processed)}.'
    )
    assert processed.shape[1] == 4, 'Every processed row must have exactly four columns.'
    assert not processed.isna().any().any(), 'processed_data.csv contains missing values.'

    counts = processed['target'].value_counts().to_dict()
    assert counts == {0: 900, 1: 900}, f'Expected balanced class counts of 900 each, got {counts}.'

    filtered = expected_filtered_raw()
    majority = filtered[filtered['target'] == 0]
    minority = filtered[filtered['target'] == 1]
    expected_minority = resample(
        minority, replace=True, n_samples=len(majority), random_state=42
    )
    expected = pd.concat([majority, expected_minority], ignore_index=True)

    assert_frame_equal(
        sorted_rows(processed), sorted_rows(expected),
        check_dtype=False, check_exact=False, rtol=1e-12, atol=1e-12
    )


def test_implemented_functions_on_independent_data():
    sys.path.insert(0, BASE)
    try:
        if 'prepare_data' in sys.modules:
            del sys.modules['prepare_data']
        import prepare_data

        synthetic = pd.DataFrame({
            'first': [0., 1., 2., 3., 4., 5.],
            'later_copy': [0., 2., 4., 6., 8., 10.],
            'independent': [0., 1., 0., 1., 1., 0.],
            'target': [0, 0, 0, 0, 0, 1],
        })
        filtered = prepare_data.filter_features(synthetic.copy())
        assert isinstance(filtered, pd.DataFrame), 'filter_features must return a DataFrame.'
        assert list(filtered.columns) == ['first', 'independent', 'target'], (
            'filter_features must drop the later member of a feature pair with absolute correlation > 0.85.'
        )

        small = pd.DataFrame({
            'x': [10, 20, 30, 99],
            'target': [0, 0, 0, 1],
        })
        balanced = prepare_data.bootstrap_balance(small.copy())
        expected_upsampled = resample(
            small[small.target == 1], replace=True, n_samples=3, random_state=42
        )
        expected_balanced = pd.concat([small[small.target == 0], expected_upsampled], ignore_index=True)
        assert_frame_equal(
            sorted_rows(balanced), sorted_rows(expected_balanced), check_dtype=False
        )
    finally:
        if BASE in sys.path:
            sys.path.remove(BASE)


def test_metrics_file():
    assert os.path.isfile(METRICS), f'Expected metrics file at {METRICS} is missing.'

    with open(METRICS, 'r') as f:
        content = f.read().strip()
    assert content != '', 'metrics.txt is empty.'

    try:
        metric_value = float(content)
    except ValueError:
        pytest.fail(f'metrics.txt does not contain a valid float. Found: {content}')

    assert np.isfinite(metric_value), 'metrics.txt must contain a finite float.'
    assert 0.0 <= metric_value <= 1.0, (
        f'F1 score should be between 0.0 and 1.0, but got {metric_value}.'
    )

    processed = pd.read_csv(PROCESSED)
    X = processed.drop('target', axis=1)
    y = processed['target']
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    model = RandomForestClassifier(random_state=42)
    model.fit(X_train, y_train)
    expected_metric = f1_score(y_test, model.predict(X_test))
    assert abs(metric_value - expected_metric) <= 0.001, (
        f'metrics.txt contains {metric_value}, but the required Random Forest evaluation gives {expected_metric}.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
