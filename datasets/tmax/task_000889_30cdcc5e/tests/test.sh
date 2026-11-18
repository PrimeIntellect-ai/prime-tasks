#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import sys
import tempfile

import librosa
import matplotlib.image as mpimg
import numpy as np
import pandas as pd
import pytest
import requests
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression

PLOT_PATH = '/home/user/pca_clusters.png'
SCRIPT_PATH = '/app/plot_clusters.py'


@pytest.fixture(scope='session')
def reference_pipeline():
    audio, sr = librosa.load('/app/subject_recordings.wav', sr=None, mono=True)
    assert len(audio) == 100 * sr

    rows = []
    for i in range(100):
        segment = audio[i * sr:(i + 1) * sr]
        mfcc = librosa.feature.mfcc(y=segment, sr=sr, n_mfcc=13)
        rows.append(mfcc.mean(axis=1))
    mfcc_features = np.asarray(rows)
    assert mfcc_features.shape == (100, 13)

    components = PCA(n_components=2).fit_transform(mfcc_features)
    metadata = pd.read_csv('/app/subject_metadata.csv')
    full = metadata.copy()
    full['pca_1'] = components[:, 0]
    full['pca_2'] = components[:, 1]

    cleaned = full.loc[full['heart_rate'] <= 150].copy()
    cleaned['age'] = cleaned['age'].fillna(cleaned['age'].median())
    features = cleaned[['pca_1', 'pca_2', 'age', 'heart_rate']]
    model = LogisticRegression().fit(features, cleaned['diagnosis'])
    return full, cleaned, model


def _points_are_covered(observed, expected, atol=1e-3):
    if not observed:
        return False
    observed = np.vstack(observed)
    observed = observed[np.isfinite(observed).all(axis=1)]
    if len(observed) == 0:
        return False
    for point in expected:
        if not np.any(np.all(np.isclose(observed, point, rtol=1e-5, atol=atol), axis=1)):
            return False
    return True


def test_plot_script_executes_and_plots_reference_pca(reference_pipeline):
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} is missing'
    if os.path.exists(PLOT_PATH):
        os.remove(PLOT_PATH)

    capture_fd, capture_path = tempfile.mkstemp(prefix='plot_capture_', suffix='.json')
    os.close(capture_fd)
    runner_path = '/tmp/run_plot_with_capture.py'
    with open(runner_path, 'w') as f:
        f.write(r'''import json
import os
import runpy
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
from matplotlib.axes import Axes

captured = []
original_scatter = Axes.scatter
original_plot = Axes.plot

def record(x, y):
    try:
        xa = np.asarray(x, dtype=float).reshape(-1)
        ya = np.asarray(y, dtype=float).reshape(-1)
        if xa.size == ya.size and xa.size >= 2:
            captured.append(np.column_stack([xa, ya]).tolist())
    except Exception:
        pass

def scatter(self, x, y, *args, **kwargs):
    record(x, y)
    return original_scatter(self, x, y, *args, **kwargs)

def plot(self, *args, **kwargs):
    if len(args) >= 2:
        record(args[0], args[1])
    return original_plot(self, *args, **kwargs)

Axes.scatter = scatter
Axes.plot = plot
os.chdir('/app')
runpy.run_path('/app/plot_clusters.py', run_name='__main__')
with open(sys.argv[1], 'w') as out:
    json.dump(captured, out)
''')

    result = subprocess.run(
        [sys.executable, runner_path, capture_path],
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'plot_clusters.py failed when executed. stdout={result.stdout!r}, '
        f'stderr={result.stderr!r}'
    )

    assert os.path.exists(PLOT_PATH), f'Plot file {PLOT_PATH} does not exist.'
    assert os.path.getsize(PLOT_PATH) > 0, f'Plot file {PLOT_PATH} is empty.'
    with open(PLOT_PATH, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', 'Plot is not a valid PNG file.'
    image = mpimg.imread(PLOT_PATH)
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100
    assert np.isfinite(image).all()
    assert float(np.std(image)) > 0.01, 'Plot appears blank or uniform.'

    with open(capture_path) as f:
        raw_captures = json.load(f)
    observed = []
    for points in raw_captures:
        arr = np.asarray(points, dtype=float)
        if arr.ndim == 2 and arr.shape[1] == 2:
            observed.append(arr)

    full, cleaned, _ = reference_pipeline
    full_points = full[['pca_1', 'pca_2']].to_numpy()
    clean_points = cleaned[['pca_1', 'pca_2']].to_numpy()
    assert (_points_are_covered(observed, full_points) or
            _points_are_covered(observed, clean_points)), (
        'The executed plot did not plot the derived pca_1 values on X and '
        'pca_2 values on Y.'
    )


def test_ping_endpoint():
    try:
        response = requests.get('http://127.0.0.1:8080/ping', timeout=3)
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Failed to connect to /ping: {e}')
    assert response.status_code == 200
    try:
        data = response.json()
    except ValueError:
        pytest.fail('Response from /ping is not valid JSON.')
    assert data.get('message') == 'pong'


def test_predict_uses_trained_reference_model(reference_pipeline):
    _, cleaned, model = reference_pipeline
    columns = ['pca_1', 'pca_2', 'age', 'heart_rate']

    # Include real cleaned rows so MFCC/PCA, outlier removal, median imputation,
    # feature ordering, and model fitting all affect the expected answers.
    real = cleaned[columns].iloc[::7].to_numpy(dtype=float)

    # Add points on both sides of this fitted model's decision boundary. This
    # ensures a constant 0 or constant 1 endpoint cannot pass.
    coef = model.coef_[0].astype(float)
    intercept = float(model.intercept_[0])
    center = cleaned[columns].median().to_numpy(dtype=float)
    norm_sq = float(np.dot(coef, coef))
    assert norm_sq > 0
    boundary = center - ((np.dot(coef, center) + intercept) / norm_sq) * coef
    margins = np.array([-8.0, -3.0, -1.0, 1.0, 3.0, 8.0])
    boundary_points = np.asarray([
        boundary + (margin / norm_sq) * coef for margin in margins
    ])
    probes = np.vstack([real, boundary_points])
    expected = model.predict(probes).astype(int)
    assert set(expected.tolist()) == {0, 1}

    for values, wanted in zip(probes, expected):
        payload = {name: float(value) for name, value in zip(columns, values)}
        try:
            response = requests.post(
                'http://127.0.0.1:8080/predict', json=payload, timeout=3
            )
        except requests.exceptions.RequestException as e:
            pytest.fail(f'Failed to connect to /predict: {e}')
        assert response.status_code == 200, response.text
        try:
            data = response.json()
        except ValueError:
            pytest.fail('Response from /predict is not valid JSON.')
        assert set(data.keys()) == {'prediction'}
        assert data['prediction'] in [0, 1]
        assert data['prediction'] == int(wanted), (
            f'Incorrect prediction for payload {payload}: expected '
            f'{int(wanted)}, got {data["prediction"]}'
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
