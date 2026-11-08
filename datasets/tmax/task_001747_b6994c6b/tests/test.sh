#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/run_submission.py
import json
import runpy
import numpy as np
from matplotlib.axes import Axes

captured = []
_original_hist = Axes.hist

def recording_hist(self, x, *args, **kwargs):
    captured.append(np.asarray(x, dtype=float).ravel().copy())
    return _original_hist(self, x, *args, **kwargs)

Axes.hist = recording_hist
runpy.run_path('/home/user/etl_validation.py', run_name='__main__')
np.savez('/tmp/captured_histograms.npz', **{
    'hist_' + str(i): values for i, values in enumerate(captured)
})
PY_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import subprocess

import numpy as np

SCRIPT = '/home/user/etl_validation.py'
METRICS = '/home/user/metrics.json'
PLOT = '/home/user/bootstrap_dist.png'
CAPTURE = '/tmp/captured_histograms.npz'


def expected_results():
    feature_1 = []
    feature_2 = []
    target = []
    with open('/home/user/data.csv', newline='') as f:
        for row in csv.DictReader(f):
            feature_1.append(float(row['feature_1']))
            feature_2.append(float(row['feature_2']))
            target.append(float(row['target']))

    target = np.asarray(target, dtype=float)
    rng = np.random.RandomState(42)
    bootstrap_means = np.asarray([
        np.mean(rng.choice(target, size=len(target), replace=True))
        for _ in range(1000)
    ])

    design = np.column_stack((np.ones(len(target)), feature_1, feature_2))
    coefficients = np.linalg.lstsq(design, target, rcond=None)[0]
    predictions = design @ coefficients
    mse = float(np.mean((target - predictions) ** 2))

    return bootstrap_means, {
        'bootstrap_mean': float(np.mean(bootstrap_means)),
        'ci_lower': float(np.percentile(bootstrap_means, 2.5)),
        'ci_upper': float(np.percentile(bootstrap_means, 97.5)),
        'model_mse': mse,
    }


def test_submission_runs_and_generates_outputs():
    assert os.path.isfile(SCRIPT), f'{SCRIPT} does not exist.'
    assert os.path.getsize(SCRIPT) > 0, f'{SCRIPT} is empty.'

    for path in (METRICS, PLOT, CAPTURE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env.pop('DISPLAY', None)
    env.pop('MPLBACKEND', None)
    result = subprocess.run(
        ['python3', '/tmp/run_submission.py'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
        env=env,
    )
    assert result.returncode == 0, (
        'etl_validation.py failed when executed headlessly.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def test_metrics_json_generated_and_correct():
    assert os.path.isfile(METRICS), f'Metrics file {METRICS} was not generated.'
    with open(METRICS) as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            assert False, f'The file {METRICS} does not contain valid JSON.'

    expected_keys = {'bootstrap_mean', 'ci_lower', 'ci_upper', 'model_mse'}
    actual_keys = set(metrics.keys())
    missing_keys = expected_keys - actual_keys
    assert not missing_keys, f'metrics.json is missing expected keys: {missing_keys}'
    assert actual_keys == expected_keys, 'metrics.json must contain exactly the required keys.'

    for key in expected_keys:
        value = metrics[key]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), f'{key} must be numeric.'
        assert math.isfinite(value), f'{key} must be finite.'

    # Retain the original fixed-value accuracy assertions.
    assert abs(metrics['ci_lower'] - 37.1265) < 0.05, 'ci_lower is incorrect.'
    assert abs(metrics['ci_upper'] - 37.9100) < 0.05, 'ci_upper is incorrect.'
    assert abs(metrics['model_mse'] - 1.0425) < 0.05, 'model_mse is incorrect.'

    _, expected = expected_results()
    for key, expected_value in expected.items():
        assert abs(metrics[key] - expected_value) < 1e-9, (
            f'{key} is incorrect: expected {expected_value}, got {metrics[key]}.'
        )


def test_bootstrap_plot_generated_and_is_required_histogram():
    assert os.path.isfile(PLOT), f'Plot file {PLOT} was not generated.'
    assert os.path.getsize(PLOT) > 0, f'Plot file {PLOT} exists but is empty.'
    with open(PLOT, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', 'bootstrap_dist.png is not a PNG image.'

    import matplotlib.image as mpimg
    image = np.asarray(mpimg.imread(PLOT))
    assert image.ndim in (2, 3), 'The PNG could not be decoded as an image.'
    assert image.shape[0] >= 100 and image.shape[1] >= 100, 'The plot image is unreasonably small.'
    assert np.isfinite(image).all(), 'The plot contains invalid pixels.'
    assert float(np.max(image) - np.min(image)) > 0.1, 'The plot is blank or visually uniform.'
    assert float(np.std(image.astype(float))) > 0.01, 'The plot does not contain meaningful content.'

    expected_bootstrap, _ = expected_results()
    assert os.path.isfile(CAPTURE), 'No matplotlib histogram was produced by the ETL script.'
    with np.load(CAPTURE) as captured:
        histograms = [np.asarray(captured[key], dtype=float) for key in captured.files]
    assert histograms, 'The ETL script did not call matplotlib histogram plotting.'
    assert any(
        values.shape == expected_bootstrap.shape
        and np.allclose(values, expected_bootstrap, rtol=0, atol=1e-12)
        for values in histograms
    ), 'bootstrap_dist.png was not built from the required 1000 bootstrap sample means.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
