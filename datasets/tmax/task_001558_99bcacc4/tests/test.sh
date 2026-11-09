#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile

import numpy as np
import pandas as pd
import pytest
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression

HOME = '/home/user'
STATE = {}


@pytest.fixture(scope='session', autouse=True)
def run_pipeline():
    pipeline = f'{HOME}/pipeline.sh'
    assert os.path.exists(pipeline), f'{pipeline} does not exist.'
    assert os.access(pipeline, os.X_OK), f'{pipeline} is not executable.'

    with open(f'{HOME}/data.csv', 'rb') as f:
        original_data = f.read()
    source_lines = original_data.splitlines(keepends=True)
    assert len(source_lines) == 1000, 'Source dataset must contain 1000 rows.'

    source_df = pd.read_csv(f'{HOME}/data.csv', header=None)
    STATE['original_data'] = original_data
    STATE['source_lines'] = source_lines
    STATE['source_df'] = source_df

    for name in ['train.csv', 'test.csv', 'train_pca.csv', 'test_pca.csv',
                 'predictions.txt', 'accuracy.txt']:
        path = f'{HOME}/{name}'
        if os.path.lexists(path):
            os.remove(path)

    env = os.environ.copy()
    env['OPENBLAS_NUM_THREADS'] = '7'
    env['OMP_NUM_THREADS'] = '7'
    subprocess.run(
        [pipeline], cwd=HOME, env=env, check=True, timeout=120,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )

    yield


def test_pipeline_script_exists_and_executable():
    path = '/home/user/pipeline.sh'
    assert os.path.exists(path), f'{path} does not exist.'
    assert os.access(path, os.X_OK), f'{path} is not executable.'


def test_pipeline_exports_thread_limits():
    path = '/home/user/pipeline.sh'
    with open(path, 'r') as f:
        script = f.read()
    for variable in ['OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS']:
        pattern = rf'(?m)^\s*export\b[^\n#]*\b{variable}\s*=\s*["\u0027]?1["\u0027]?(?:\s|$)'
        assert re.search(pattern, script), f'{variable}=1 is not exported by pipeline.sh.'


def test_python_scripts_exist():
    for script in ['pca.py', 'train.py']:
        path = f'/home/user/{script}'
        assert os.path.exists(path), f'{path} does not exist.'
        assert os.path.isfile(path), f'{path} is not a regular file.'


def test_source_data_was_not_modified():
    with open(f'{HOME}/data.csv', 'rb') as f:
        assert f.read() == STATE['original_data']


def test_csv_splits():
    train_path = '/home/user/train.csv'
    test_path = '/home/user/test.csv'

    assert os.path.exists(train_path), f'{train_path} does not exist.'
    assert os.path.exists(test_path), f'{test_path} does not exist.'

    with open(train_path, 'r') as f:
        train_lines = sum(1 for _ in f)
    assert train_lines == 800, f'Expected 800 lines in {train_path}, found {train_lines}.'

    with open(test_path, 'r') as f:
        test_lines = sum(1 for _ in f)
    assert test_lines == 200, f'Expected 200 lines in {test_path}, found {test_lines}.'

    with open(train_path, 'rb') as f:
        assert f.read() == b''.join(STATE['source_lines'][:800]), \
            'train.csv is not exactly the first 800 source rows.'
    with open(test_path, 'rb') as f:
        assert f.read() == b''.join(STATE['source_lines'][800:]), \
            'test.csv is not exactly the remaining 200 source rows.'


def test_pipeline_pca_outputs():
    source = STATE['source_df']
    train = source.iloc[:800]
    test = source.iloc[800:]

    model = PCA(n_components=5, svd_solver='full')
    expected_train_x = model.fit_transform(train.iloc[:, :10].to_numpy())
    expected_test_x = model.transform(test.iloc[:, :10].to_numpy())

    train_out = pd.read_csv(f'{HOME}/train_pca.csv', header=None)
    test_out = pd.read_csv(f'{HOME}/test_pca.csv', header=None)
    assert train_out.shape == (800, 6)
    assert test_out.shape == (200, 6)
    assert np.isfinite(train_out.to_numpy()).all()
    assert np.isfinite(test_out.to_numpy()).all()
    np.testing.assert_allclose(train_out.iloc[:, :5].to_numpy(), expected_train_x,
                               rtol=1e-6, atol=1e-7)
    np.testing.assert_allclose(test_out.iloc[:, :5].to_numpy(), expected_test_x,
                               rtol=1e-6, atol=1e-7)
    np.testing.assert_array_equal(train_out.iloc[:, 5].to_numpy(), train.iloc[:, 10].to_numpy())
    np.testing.assert_array_equal(test_out.iloc[:, 5].to_numpy(), test.iloc[:, 10].to_numpy())


def test_pipeline_predictions():
    source = STATE['source_df']
    train = source.iloc[:800]
    test = source.iloc[800:]
    pca = PCA(n_components=5, svd_solver='full')
    train_x = pca.fit_transform(train.iloc[:, :10].to_numpy())
    test_x = pca.transform(test.iloc[:, :10].to_numpy())
    expected = LogisticRegression(random_state=42).fit(
        train_x, train.iloc[:, 10].to_numpy()
    ).predict(test_x).astype(int)

    path = f'{HOME}/predictions.txt'
    assert os.path.exists(path), f'{path} does not exist.'
    with open(path, 'r') as f:
        lines = f.read().splitlines()
    assert len(lines) == 200, f'Expected 200 predictions, found {len(lines)}.'
    assert all(line.strip() in {'0', '1'} for line in lines), \
        'predictions.txt must contain only one binary label per line.'
    actual = np.array([int(line.strip()) for line in lines])
    np.testing.assert_array_equal(actual, expected)


def test_accuracy_result():
    path = '/home/user/accuracy.txt'
    assert os.path.exists(path), f'{path} does not exist.'

    with open(path, 'r') as f:
        content = f.read().strip()
    assert len(content.split()) == 1, f'{path} must contain one floating-point number.'

    try:
        accuracy = float(content)
    except ValueError:
        assert False, f"Could not parse '{content}' as a float in {path}."

    with open(f'{HOME}/predictions.txt', 'r') as f:
        predictions = np.array([int(line.strip()) for line in f if line.strip()])
    labels = STATE['source_df'].iloc[800:, 10].to_numpy().astype(int)
    expected_accuracy = float(np.mean(predictions == labels))
    assert abs(accuracy - expected_accuracy) < 1e-12, \
        f'Accuracy file has {accuracy}, but predictions imply {expected_accuracy}.'
    assert abs(accuracy - 0.825) < 1e-4, f'Expected accuracy to be 0.825, but got {accuracy}.'


def test_pca_script_command_line_behavior():
    rng = np.random.RandomState(731)
    train_x = rng.normal(size=(37, 10))
    test_x = rng.normal(loc=0.4, scale=1.3, size=(13, 10))
    train_y = (np.arange(37) % 2).astype(int)
    test_y = (np.arange(13) % 2).astype(int)

    with tempfile.TemporaryDirectory() as tmp:
        train_in = os.path.join(tmp, 'input_train.csv')
        test_in = os.path.join(tmp, 'input_test.csv')
        train_out = os.path.join(tmp, 'output_train.csv')
        test_out = os.path.join(tmp, 'output_test.csv')
        np.savetxt(train_in, np.column_stack([train_x, train_y]), delimiter=',')
        np.savetxt(test_in, np.column_stack([test_x, test_y]), delimiter=',')
        env = os.environ.copy()
        env['OPENBLAS_NUM_THREADS'] = '1'
        env['OMP_NUM_THREADS'] = '1'
        subprocess.run(
            ['python3', f'{HOME}/pca.py', train_in, test_in, train_out, test_out],
            check=True, timeout=60, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        actual_train = np.loadtxt(train_out, delimiter=',', ndmin=2)
        actual_test = np.loadtxt(test_out, delimiter=',', ndmin=2)

    reference = PCA(n_components=5, svd_solver='full')
    expected_train = reference.fit_transform(train_x)
    expected_test = reference.transform(test_x)
    assert actual_train.shape == (37, 6)
    assert actual_test.shape == (13, 6)
    np.testing.assert_allclose(actual_train[:, :5], expected_train, rtol=1e-6, atol=1e-7)
    np.testing.assert_allclose(actual_test[:, :5], expected_test, rtol=1e-6, atol=1e-7)
    np.testing.assert_array_equal(actual_train[:, 5], train_y)
    np.testing.assert_array_equal(actual_test[:, 5], test_y)


def test_train_script_command_line_behavior():
    rng = np.random.RandomState(991)
    train_x = rng.normal(size=(80, 5))
    test_x = rng.normal(size=(21, 5))
    weights = np.array([1.8, -1.2, 0.7, 0.4, -0.9])
    train_y = (train_x @ weights + rng.normal(scale=0.35, size=80) > 0).astype(int)
    test_y = (test_x @ weights > 0).astype(int)

    with tempfile.TemporaryDirectory() as tmp:
        train_in = os.path.join(tmp, 'train_pca.csv')
        test_in = os.path.join(tmp, 'test_pca.csv')
        output = os.path.join(tmp, 'predictions.txt')
        np.savetxt(train_in, np.column_stack([train_x, train_y]), delimiter=',')
        np.savetxt(test_in, np.column_stack([test_x, test_y]), delimiter=',')
        env = os.environ.copy()
        env['OPENBLAS_NUM_THREADS'] = '1'
        env['OMP_NUM_THREADS'] = '1'
        subprocess.run(
            ['python3', f'{HOME}/train.py', train_in, test_in, output],
            check=True, timeout=60, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        with open(output, 'r') as f:
            lines = f.read().splitlines()

    assert len(lines) == 21
    assert all(line.strip() in {'0', '1'} for line in lines)
    actual = np.array([int(line.strip()) for line in lines])
    expected = LogisticRegression(random_state=42).fit(train_x, train_y).predict(test_x)
    np.testing.assert_array_equal(actual, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
