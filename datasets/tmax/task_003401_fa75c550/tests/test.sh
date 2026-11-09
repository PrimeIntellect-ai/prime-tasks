#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pickle
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import Ridge

HOME = Path('/home/user')
RAW = Path('/app/data.csv')
ENGINEER = HOME / 'engineer.R'
ENGINEERED = HOME / 'engineered.csv'
TRAIN = HOME / 'train.py'
MODEL = HOME / 'model.pkl'
FEATURES = ['f2', 'f4', 'f5', 'f8']


def load_model(path=MODEL):
    try:
        with open(path, 'rb') as f:
            return pickle.load(f)
    except Exception as e:
        pytest.fail(f'Failed to load the model pickle file: {e}')


def run_train_requiring_env_setup():
    with tempfile.TemporaryDirectory() as td:
        marker = Path(td) / 'ridge_fit_called'
        sitecustomize = Path(td) / 'sitecustomize.py'
        sitecustomize.write_text(
            "import os\n"
            "from sklearn.linear_model import Ridge\n"
            "_original_fit = Ridge.fit\n"
            "def _checked_fit(self, X, y, *args, **kwargs):\n"
            "    if os.environ.get('OMP_NUM_THREADS') != '1':\n"
            "        raise RuntimeError('OMP_NUM_THREADS must be set to 1 before model training')\n"
            "    with open(os.environ['RIDGE_FIT_MARKER'], 'w') as f:\n"
            "        f.write('1')\n"
            "    return _original_fit(self, X, y, *args, **kwargs)\n"
            "Ridge.fit = _checked_fit\n"
        )
        env = os.environ.copy()
        env.pop('OMP_NUM_THREADS', None)
        env['RIDGE_FIT_MARKER'] = str(marker)
        env['PYTHONPATH'] = td + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
        subprocess.run(
            ['python3', str(TRAIN)], cwd=str(HOME), env=env,
            check=True, timeout=60
        )
        assert marker.exists(), 'train.py did not call Ridge.fit'


def test_requested_pipeline_is_executable_and_correct():
    assert ENGINEER.is_file(), f'R script not found at {ENGINEER}'
    assert TRAIN.is_file(), f'Training script not found at {TRAIN}'
    assert ENGINEER.stat().st_size > 0, 'engineer.R is empty'
    assert TRAIN.stat().st_size > 0, 'train.py is empty'

    original_raw = RAW.read_bytes()
    try:
        rng = np.random.default_rng(int.from_bytes(os.urandom(8), 'little'))
        n = 83
        raw = pd.DataFrame(rng.normal(size=(n, 10)), columns=[f'f{i}' for i in range(1, 11)])
        raw['y'] = (4.1 * raw['f2'] - 2.3 * raw['f4'] + 1.7 * raw['f5'] +
                    0.6 * raw['f8'] + rng.normal(scale=0.2, size=n))
        raw.to_csv(RAW, index=False)

        subprocess.run(['Rscript', str(ENGINEER)], check=True, timeout=60)
        assert ENGINEERED.is_file(), f'Engineered dataset not found at {ENGINEERED}'
        engineered = pd.read_csv(ENGINEERED)

        assert list(engineered.columns) == FEATURES + ['y'], (
            'engineered.csv must contain only f2, f4, f5, f8, and y in that order'
        )
        assert engineered.shape == (n, 5), 'engineered.csv has the wrong shape'
        expected_x = (raw[FEATURES] - raw[FEATURES].mean()) / raw[FEATURES].std(ddof=1)
        np.testing.assert_allclose(
            engineered[FEATURES].to_numpy(), expected_x.to_numpy(),
            rtol=1e-7, atol=1e-7,
            err_msg='engineer.R did not z-score the requested features correctly'
        )
        np.testing.assert_allclose(
            engineered['y'].to_numpy(), raw['y'].to_numpy(),
            rtol=1e-10, atol=1e-10,
            err_msg='engineer.R must preserve the target y'
        )

        run_train_requiring_env_setup()
        model = load_model()
        assert type(model) is Ridge, 'model.pkl must contain a scikit-learn Ridge model'
        assert float(model.alpha) == pytest.approx(0.5), 'Ridge alpha must be exactly 0.5'

        expected_model = Ridge(alpha=0.5).fit(engineered[FEATURES], engineered['y'])
        probe = rng.normal(size=(31, 4))
        np.testing.assert_allclose(
            model.predict(probe), expected_model.predict(probe),
            rtol=1e-7, atol=1e-7,
            err_msg='train.py did not train Ridge(alpha=0.5) from engineered.csv'
        )
    finally:
        RAW.write_bytes(original_raw)

    # Recreate the requested final artifacts from the original dataset.
    subprocess.run(['Rscript', str(ENGINEER)], check=True, timeout=60)
    env = os.environ.copy()
    env['OMP_NUM_THREADS'] = '1'
    subprocess.run(['python3', str(TRAIN)], cwd=str(HOME), env=env, check=True, timeout=60)


def test_model_mse():
    model_path = '/home/user/model.pkl'
    assert os.path.exists(model_path), f"Model file not found at {model_path}"

    # Generate test set
    np.random.seed(999)
    n_samples = 500
    X_test = np.random.randn(n_samples, 10)
    y_test = 3.0 * X_test[:, 1] - 1.5 * X_test[:, 3] + 2.0 * X_test[:, 4] + 0.8 * X_test[:, 7] + np.random.randn(n_samples) * 0.5

    # Extract features used in training (f2, f4, f5, f8)
    X_test_filtered = X_test[:, [1, 3, 4, 7]]

    # Scale test features using sample statistics
    X_test_scaled = (X_test_filtered - np.mean(X_test_filtered, axis=0)) / np.std(X_test_filtered, axis=0)

    model = load_model(Path(model_path))

    try:
        preds = model.predict(X_test_scaled)
    except Exception as e:
        pytest.fail(f"Failed to predict using the loaded model: {e}")

    mse = np.mean((y_test - preds)**2)
    assert mse <= 2.5, f"MSE {mse:.4f} is greater than the threshold of 2.5"


def test_engineered_data_exists():
    data_path = '/home/user/engineered.csv'
    assert os.path.exists(data_path), f"Engineered dataset not found at {data_path}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
