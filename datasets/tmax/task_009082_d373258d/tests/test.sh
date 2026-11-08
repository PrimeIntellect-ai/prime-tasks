#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import importlib.util
import json
import math
import os
import subprocess

import matplotlib.image as mpimg
import numpy as np
import pandas as pd

SCRIPT = '/home/user/etl_pipeline.py'
DATA = '/home/user/sensor_data.csv'
WEIGHTS = '/home/user/model_weights.json'
METRICS = '/home/user/pipeline_metrics.json'
PLOT = '/home/user/inference_plot.png'


def expected_results(data_path=DATA, weights_path=WEIGHTS):
    df = pd.read_csv(data_path)
    median = float(df['X'].median())
    x = df['X'].fillna(median).clip(-10.0, 10.0).to_numpy().reshape(-1, 1)
    with open(weights_path, 'r') as f:
        w = {k: np.asarray(v, dtype=float) for k, v in json.load(f).items()}
    hidden = np.maximum(0.0, np.dot(x, w['W1']) + w['b1'])
    predictions = np.dot(hidden, w['W2']) + w['b2']
    return median, float(np.mean(predictions))


def run_pipeline():
    for path in (METRICS, PLOT):
        if os.path.lexists(path):
            os.remove(path)
    result = subprocess.run(
        ['python3', SCRIPT], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert result.returncode == 0, f'Pipeline failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
    assert os.path.isfile(METRICS), f'Expected metrics file not found at {METRICS}'
    assert os.path.isfile(PLOT), f'Expected plot file not found at {PLOT}'
    assert os.path.getsize(PLOT) > 0, f'Plot file {PLOT} is empty'


def check_outputs(expected_median, expected_mean):
    with open(METRICS, 'r') as f:
        metrics = json.load(f)

    assert set(metrics) == {'median_imputed', 'mean_prediction', 'inference_time_seconds'}
    for key in metrics:
        assert isinstance(metrics[key], (int, float)) and not isinstance(metrics[key], bool), f'{key} must be a number'
        assert math.isfinite(metrics[key]), f'{key} must be finite'

    assert math.isclose(metrics['median_imputed'], expected_median, rel_tol=0, abs_tol=1e-9)
    assert math.isclose(metrics['mean_prediction'], expected_mean, rel_tol=0, abs_tol=1e-9)
    assert metrics['inference_time_seconds'] > 0

    with open(PLOT, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', 'Plot is not a PNG file'
    image = mpimg.imread(PLOT)
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100
    assert np.isfinite(image).all()
    assert float(np.max(image) - np.min(image)) > 0.05, 'Plot appears blank'

    return hashlib.sha256(open(PLOT, 'rb').read()).hexdigest()


def test_pipeline_end_to_end_and_predict():
    assert os.path.isfile(SCRIPT), f'Expected executable Python artifact at {SCRIPT}'

    # Execute against the supplied files and retain the original verifier's checks.
    original_median, original_mean = expected_results()
    run_pipeline()
    original_plot_hash = check_outputs(original_median, original_mean)
    assert math.isclose(original_median, -0.0617336, abs_tol=0.01)
    assert math.isclose(original_mean, 10.84439, abs_tol=0.01)

    # Exercise predict directly on values for which omitting ReLU changes the answer.
    spec = importlib.util.spec_from_file_location('submitted_etl_pipeline', SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    custom_x = np.array([[-3.0], [0.0], [2.0]])
    custom_w = {
        'W1': np.array([[2.0, -1.0]]),
        'b1': np.array([0.5, 0.0]),
        'W2': np.array([[1.5], [0.5]]),
        'b2': np.array([-1.0]),
    }
    expected = np.maximum(0.0, custom_x @ custom_w['W1'] + custom_w['b1']) @ custom_w['W2'] + custom_w['b2']
    actual = np.asarray(module.predict(custom_x, custom_w))
    assert actual.shape == expected.shape
    assert np.allclose(actual, expected, rtol=0, atol=1e-12), 'predict must apply ReLU before the output layer'

    # Run on an unpredictable dataset so hardcoded metrics or a pre-created plot fail.
    data_backup = open(DATA, 'rb').read()
    weights_backup = open(WEIGHTS, 'rb').read()
    try:
        rng = np.random.default_rng(int.from_bytes(os.urandom(8), 'big'))
        values = rng.normal(rng.uniform(-2.0, 2.0), 4.0, 4096)
        values[rng.choice(len(values), 173, replace=False)] = np.nan
        finite_indices = np.flatnonzero(~np.isnan(values))
        values[rng.choice(finite_indices, 90, replace=False)] = 1000.0
        finite_indices = np.flatnonzero(~np.isnan(values))
        values[rng.choice(finite_indices, 90, replace=False)] = -1000.0
        pd.DataFrame({'X': values}).to_csv(DATA, index=False)

        challenge_weights = {
            'W1': [[1.7, -0.8]],
            'b1': [0.25, 0.4],
            'W2': [[1.2], [-0.7]],
            'b2': [0.15]
        }
        with open(WEIGHTS, 'w') as f:
            json.dump(challenge_weights, f)

        challenge_median, challenge_mean = expected_results()
        run_pipeline()
        challenge_plot_hash = check_outputs(challenge_median, challenge_mean)
        assert challenge_plot_hash != original_plot_hash, 'Plot was not regenerated from the cleaned data and predictions'
    finally:
        with open(DATA, 'wb') as f:
            f.write(data_backup)
        with open(WEIGHTS, 'wb') as f:
            f.write(weights_backup)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
