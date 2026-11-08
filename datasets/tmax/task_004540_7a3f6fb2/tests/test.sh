#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import shlex
import shutil
import subprocess
import sys
import tempfile

import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error

RUN_SCRIPT = '/home/user/run.sh'
PIPELINE = '/home/user/pipeline.py'
H5_FILE = '/home/user/processed_data/clean_data.h5'
METRICS_FILE = '/home/user/metrics.json'
EXPECTED_ENV = {
    'PYTHONHASHSEED': '42',
    'OMP_NUM_THREADS': '1',
    'OPENBLAS_NUM_THREADS': '1',
    'MKL_NUM_THREADS': '1',
}


@pytest.fixture(scope='session', autouse=True)
def execute_pipeline():
    assert os.path.isfile(RUN_SCRIPT), f'{RUN_SCRIPT} does not exist.'
    assert os.access(RUN_SCRIPT, os.X_OK), f'{RUN_SCRIPT} is not executable.'
    assert os.path.isfile(PIPELINE), f'{PIPELINE} does not exist.'

    os.makedirs('/home/user/processed_data', exist_ok=True)
    for path in (H5_FILE, METRICS_FILE):
        if os.path.lexists(path):
            os.remove(path)

    shim_dir = tempfile.mkdtemp(prefix='verifier-python-')
    record_file = os.path.join(shim_dir, 'invocation.txt')
    shim = os.path.join(shim_dir, 'python')
    with open(shim, 'w') as f:
        f.write(
            '#!/bin/bash\n'
            "printf '%s\\n' \"${PYTHONHASHSEED-}\" \"${OMP_NUM_THREADS-}\" "
            "\"${OPENBLAS_NUM_THREADS-}\" \"${MKL_NUM_THREADS-}\" "
            "\"$#\" \"${1-}\" > " + shlex.quote(record_file) + "\n"
            'exec ' + shlex.quote(sys.executable) + ' "$@"\n'
        )
    os.chmod(shim, 0o755)

    env = os.environ.copy()
    for name in EXPECTED_ENV:
        env.pop(name, None)
    env['PATH'] = shim_dir + os.pathsep + env.get('PATH', '')

    try:
        result = subprocess.run(
            [RUN_SCRIPT],
            cwd='/home/user',
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=180,
        )
        assert result.returncode == 0, f'run.sh failed with output:\n{result.stdout}'
        assert os.path.isfile(record_file), (
            'run.sh did not execute `python /home/user/pipeline.py` through PATH.'
        )
        with open(record_file) as f:
            invocation = f.read().splitlines()
        assert invocation == ['42', '1', '1', '1', '1', PIPELINE], (
            'run.sh must export the required values and execute exactly '
            '`python /home/user/pipeline.py`; observed: ' + repr(invocation)
        )
    finally:
        shutil.rmtree(shim_dir, ignore_errors=True)


def expected_clean_data():
    paths = [f'/home/user/raw_data/data_{i}.csv' for i in range(3)]
    frames = [pd.read_csv(path) for path in paths]
    data = pd.concat(frames, axis=0)
    return data[
        data['target'].notna()
        & data['feature_0'].between(-10.0, 10.0, inclusive='both')
    ]


def test_run_sh_exists_and_executable():
    assert os.path.isfile(RUN_SCRIPT), f'{RUN_SCRIPT} does not exist.'
    assert os.access(RUN_SCRIPT, os.X_OK), f'{RUN_SCRIPT} is not executable.'


def test_pipeline_py_exists():
    assert os.path.isfile(PIPELINE), f'{PIPELINE} does not exist.'


def test_run_sh_environment_variables():
    with open(RUN_SCRIPT, 'r') as f:
        content = f.read()

    expected_exports = [
        'PYTHONHASHSEED=42',
        'OMP_NUM_THREADS=1',
        'OPENBLAS_NUM_THREADS=1',
        'MKL_NUM_THREADS=1',
    ]
    normalized = content.replace(' ', '').replace('"', '').replace("'", '')
    for exp in expected_exports:
        assert exp in normalized, f'Expected export {exp} not found in run.sh.'


def test_processed_data_exists_and_is_correct():
    assert os.path.isfile(H5_FILE), f'{H5_FILE} does not exist.'

    with pd.HDFStore(H5_FILE, mode='r') as store:
        assert store.keys() == ['/dataset'], (
            "HDF5 file must contain exactly the key 'dataset'."
        )
        actual = store['dataset']

    expected = expected_clean_data()
    expected_columns = [f'feature_{i}' for i in range(10)] + ['target']
    assert list(actual.columns) == expected_columns
    assert len(actual) == len(expected)
    assert actual['target'].notna().all()
    assert actual['feature_0'].between(-10.0, 10.0, inclusive='both').all()

    pd.testing.assert_frame_equal(
        actual.reset_index(drop=True),
        expected.reset_index(drop=True),
        check_exact=False,
        rtol=1e-12,
        atol=1e-12,
    )


def test_metrics_json_exists_and_content():
    assert os.path.isfile(METRICS_FILE), f'{METRICS_FILE} does not exist.'

    with open(METRICS_FILE, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('metrics.json is not a valid JSON file.')

    assert 'mse' in metrics, "Key 'mse' missing in metrics.json"
    assert 'coef_sum' in metrics, "Key 'coef_sum' missing in metrics.json"
    assert isinstance(metrics['mse'], (int, float)), 'MSE should be a number.'
    assert isinstance(metrics['coef_sum'], (int, float)), 'coef_sum should be a number.'
    assert math.isfinite(metrics['mse']), 'MSE must be finite.'
    assert math.isfinite(metrics['coef_sum']), 'coef_sum must be finite.'

    cleaned = expected_clean_data()
    feature_columns = [f'feature_{i}' for i in range(10)]
    model = Ridge(alpha=1.0, random_state=42)
    model.fit(cleaned[feature_columns], cleaned['target'])
    expected_mse = mean_squared_error(
        cleaned['target'], model.predict(cleaned[feature_columns])
    )
    expected_coef_sum = float(np.sum(model.coef_))

    assert math.isclose(metrics['mse'], expected_mse, rel_tol=1e-10, abs_tol=1e-10), (
        f"Incorrect MSE: expected {expected_mse}, got {metrics['mse']}"
    )
    assert math.isclose(
        metrics['coef_sum'], expected_coef_sum, rel_tol=1e-10, abs_tol=1e-10
    ), f"Incorrect coefficient sum: expected {expected_coef_sum}, got {metrics['coef_sum']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
