#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import stat
import subprocess

import numpy as np
import pandas as pd
import pytest
from sklearn.datasets import make_regression
from sklearn.decomposition import PCA
from sklearn.linear_model import BayesianRidge

HOME = '/home/user'
GENERATED = [
    'train_raw.csv', 'test_raw.csv', 'train_pca.csv', 'test_pca.csv',
    'predictions.csv', 'mse_result.txt'
]


def canonical_data():
    X, y = make_regression(
        n_samples=1000, n_features=19, n_informative=5,
        noise=0.5, random_state=42
    )
    df = pd.DataFrame(X, columns=[f'feature_{i+1}' for i in range(19)])
    df.insert(0, 'id', range(1, 1001))
    df['target'] = y
    return df


@pytest.fixture(scope='session', autouse=True)
def execute_pipeline():
    raw_path = os.path.join(HOME, 'raw_data.csv')
    assert os.path.isfile(raw_path), f'{raw_path} does not exist.'

    actual_raw = pd.read_csv(raw_path)
    expected_raw = canonical_data()
    assert list(actual_raw.columns) == list(expected_raw.columns), 'raw_data.csv columns were changed.'
    assert actual_raw.shape == expected_raw.shape, 'raw_data.csv shape was changed.'
    assert np.allclose(actual_raw.to_numpy(dtype=float), expected_raw.to_numpy(dtype=float), rtol=1e-12, atol=1e-12), \
        'raw_data.csv does not match the provided dataset.'

    for name in GENERATED:
        path = os.path.join(HOME, name)
        if os.path.lexists(path):
            if os.path.isdir(path):
                raise AssertionError(f'Expected output path is a directory: {path}')
            os.remove(path)

    result = subprocess.run(
        [os.path.join(HOME, 'run_pipeline.sh')],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f'run_pipeline.sh failed:\n{result.stdout}'


def expected_results():
    raw = canonical_data()
    train = raw.iloc[:800].reset_index(drop=True)
    test = raw.iloc[800:].reset_index(drop=True)
    feature_cols = [f'feature_{i}' for i in range(1, 20)]
    pca = PCA(n_components=3, random_state=42)
    train_components = pca.fit_transform(train[feature_cols])
    test_components = pca.transform(test[feature_cols])
    model = BayesianRidge()
    model.fit(train_components, train['target'].to_numpy())
    predictions = model.predict(test_components)
    return train, test, train_components, test_components, predictions


def assert_pca_file(path, source, expected_components):
    assert os.path.isfile(path), f'{path} does not exist.'
    frame = pd.read_csv(path)
    assert len(frame) == len(source), f'{path} has the wrong row count.'
    assert 'id' in frame.columns and 'target' in frame.columns, f'{path} must include id and target.'
    component_cols = [c for c in frame.columns if c not in ('id', 'target')]
    assert len(component_cols) == 3, f'{path} must contain exactly three PCA components.'
    assert np.array_equal(frame['id'].to_numpy(), source['id'].to_numpy()), f'{path} has incorrect ids.'
    assert np.allclose(frame['target'].to_numpy(dtype=float), source['target'].to_numpy(dtype=float), rtol=1e-10, atol=1e-10), \
        f'{path} has incorrect targets.'
    actual = frame[component_cols].to_numpy(dtype=float)
    assert np.isfinite(actual).all(), f'{path} contains non-finite PCA values.'
    for index in range(3):
        same = np.allclose(actual[:, index], expected_components[:, index], rtol=1e-7, atol=1e-7)
        flipped = np.allclose(actual[:, index], -expected_components[:, index], rtol=1e-7, atol=1e-7)
        assert same or flipped, f'PCA component {index + 1} in {path} is incorrect.'


def assert_predictions(path, expected_ids, expected_values):
    assert os.path.isfile(path), f'{path} does not exist.'
    frame = pd.read_csv(path)
    assert list(frame.columns) == ['id', 'predicted_target'], f'predictions.csv headers are incorrect: {list(frame.columns)}'
    assert len(frame) == 200, f'predictions.csv should have 200 data rows, found {len(frame)}.'
    assert np.array_equal(frame['id'].to_numpy(), expected_ids), 'predictions.csv ids are incorrect or out of order.'
    values = frame['predicted_target'].to_numpy(dtype=float)
    assert np.isfinite(values).all(), 'predictions.csv contains non-finite predictions.'
    assert np.allclose(values, expected_values, rtol=1e-7, atol=1e-7), \
        'predictions.csv does not contain the required PCA + BayesianRidge predictions.'


def test_pipeline_script_exists_and_executable():
    script_path = '/home/user/run_pipeline.sh'
    assert os.path.exists(script_path), f'{script_path} does not exist.'
    assert os.path.isfile(script_path), f'{script_path} is not a file.'
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f'{script_path} is not executable by the user.'


def test_python_scripts_exist():
    for script in ['pca_transform.py', 'bayesian_train_predict.py']:
        path = f'/home/user/{script}'
        assert os.path.exists(path), f'Python script {path} does not exist.'
        assert os.path.isfile(path), f'{path} is not a file.'


def test_generated_csv_files_exist():
    for filename in ['train_raw.csv', 'test_raw.csv', 'train_pca.csv', 'test_pca.csv', 'predictions.csv']:
        path = f'/home/user/{filename}'
        assert os.path.exists(path), f'Expected generated file {path} does not exist.'
        assert os.path.isfile(path), f'{path} is not a file.'


def test_split_files_row_counts_and_contents():
    def count_rows(filepath):
        with open(filepath, 'r', newline='') as f:
            return sum(1 for _ in f)

    assert count_rows('/home/user/train_raw.csv') == 801, 'train_raw.csv should have 801 rows (including header).'
    assert count_rows('/home/user/test_raw.csv') == 201, 'test_raw.csv should have 201 rows (including header).'

    expected_train, expected_test, _, _, _ = expected_results()
    train = pd.read_csv('/home/user/train_raw.csv')
    test = pd.read_csv('/home/user/test_raw.csv')
    assert list(train.columns) == list(expected_train.columns), 'train_raw.csv has incorrect columns.'
    assert list(test.columns) == list(expected_test.columns), 'test_raw.csv has incorrect columns.'
    assert np.allclose(train.to_numpy(dtype=float), expected_train.to_numpy(dtype=float), rtol=1e-12, atol=1e-12), \
        'train_raw.csv is not the first 800 rows of raw_data.csv.'
    assert np.allclose(test.to_numpy(dtype=float), expected_test.to_numpy(dtype=float), rtol=1e-12, atol=1e-12), \
        'test_raw.csv is not the final 200 rows of raw_data.csv.'


def test_pca_outputs_are_correct():
    train, test, train_components, test_components, _ = expected_results()
    assert_pca_file('/home/user/train_pca.csv', train, train_components)
    assert_pca_file('/home/user/test_pca.csv', test, test_components)


def test_predictions_format_and_values():
    _, test, _, _, expected_predictions = expected_results()
    assert_predictions('/home/user/predictions.csv', test['id'].to_numpy(), expected_predictions)


def test_python_scripts_execute_the_required_stages():
    train, test, train_components, test_components, expected_predictions = expected_results()

    for name in ['train_pca.csv', 'test_pca.csv']:
        path = os.path.join(HOME, name)
        if os.path.exists(path):
            os.remove(path)
    pca_run = subprocess.run(
        ['python3', '/home/user/pca_transform.py', 'train_raw.csv', 'test_raw.csv'],
        cwd=HOME, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
    )
    assert pca_run.returncode == 0, f'pca_transform.py failed:\n{pca_run.stdout}'
    assert_pca_file('/home/user/train_pca.csv', train, train_components)
    assert_pca_file('/home/user/test_pca.csv', test, test_components)

    pred_path = '/home/user/predictions.csv'
    if os.path.exists(pred_path):
        os.remove(pred_path)
    model_run = subprocess.run(
        ['python3', '/home/user/bayesian_train_predict.py'],
        cwd=HOME, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
    )
    assert model_run.returncode == 0, f'bayesian_train_predict.py failed:\n{model_run.stdout}'
    assert_predictions(pred_path, test['id'].to_numpy(), expected_predictions)


def test_mse_calculation():
    mse_file = '/home/user/mse_result.txt'
    assert os.path.exists(mse_file), f'{mse_file} does not exist.'
    with open(mse_file, 'r') as f:
        content = f.read().strip()

    try:
        reported_mse = float(content)
    except ValueError:
        pytest.fail(f"Content of {mse_file} is not a valid float: '{content}'")
    assert np.isfinite(reported_mse), 'Reported MSE must be finite.'

    preds = {}
    with open('/home/user/predictions.csv', 'r', newline='') as f:
        for row in csv.DictReader(f):
            assert row['id'] not in preds, f"Duplicate prediction id: {row['id']}"
            preds[row['id']] = float(row['predicted_target'])

    actual_targets = {}
    with open('/home/user/test_raw.csv', 'r', newline='') as f:
        for row in csv.DictReader(f):
            actual_targets[row['id']] = float(row['target'])

    assert len(preds) == len(actual_targets), 'Mismatch in number of predictions and actual targets.'
    squared_errors = []
    for id_val, pred_val in preds.items():
        assert id_val in actual_targets, f'ID {id_val} from predictions not found in test_raw.csv'
        squared_errors.append((pred_val - actual_targets[id_val]) ** 2)

    calculated_mse = sum(squared_errors) / len(squared_errors)
    expected_mse_str = f'{calculated_mse:.2f}'
    assert content == expected_mse_str, \
        f'Reported MSE ({content}) does not match the computed MSE rounded to 2 decimals ({expected_mse_str}).'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
