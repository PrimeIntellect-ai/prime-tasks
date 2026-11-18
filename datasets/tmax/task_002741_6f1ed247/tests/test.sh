#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import os
import subprocess

import duckdb
import numpy as np
import pandas as pd
import pandas.testing as pdt
from sklearn.linear_model import LogisticRegression, Ridge
from sklearn.metrics import accuracy_score, mean_squared_error

HOME = '/home/user'


def run(command):
    subprocess.run(command, cwd=HOME, check=True, timeout=180)


def canonical_data():
    np.random.seed(100)
    n = 5000
    return pd.DataFrame({
        'id': range(n),
        'f1': np.random.randn(n),
        'f2': np.random.randn(n) * 2 + 1,
        'f3': np.random.rand(n),
        'f4': np.random.randn(n) - 1,
        'f5': np.random.randint(0, 10, n),
        'is_high_value': np.random.randint(0, 2, n),
        'score': np.random.randn(n) * 10 + 50,
    })


def assert_frame_matches(actual, expected):
    pdt.assert_frame_equal(
        actual.reset_index(drop=True),
        expected.reset_index(drop=True),
        check_dtype=False,
        check_exact=False,
        rtol=1e-12,
        atol=1e-12,
    )


def validate_outputs(train, test):
    features = ['f1', 'f2', 'f3', 'f4', 'f5']
    classifier = LogisticRegression(random_state=42)
    regressor = Ridge(alpha=1.0, random_state=42)
    classifier.fit(train[features], train['is_high_value'])
    regressor.fit(train[features], train['score'])

    expected_class = classifier.predict(test[features])
    expected_score = regressor.predict(test[features])
    expected_accuracy = accuracy_score(
        train['is_high_value'], classifier.predict(train[features])
    )
    expected_mse = mean_squared_error(
        train['score'], regressor.predict(train[features])
    )

    predictions = pd.read_csv('/home/user/predictions.csv')
    assert list(predictions.columns) == ['id', 'class_pred', 'score_pred']
    assert len(predictions) == 1000
    np.testing.assert_array_equal(predictions['id'].to_numpy(), test['id'].to_numpy())
    np.testing.assert_array_equal(predictions['class_pred'].to_numpy(), expected_class)
    assert np.isfinite(predictions['score_pred'].to_numpy()).all()
    np.testing.assert_allclose(
        predictions['score_pred'].to_numpy(), expected_score, rtol=1e-10, atol=1e-10
    )

    with open('/home/user/metrics.json', 'r') as f:
        metrics = json.load(f)
    assert set(metrics) == {'classification_accuracy', 'regression_mse'}
    assert isinstance(metrics['classification_accuracy'], (int, float))
    assert isinstance(metrics['regression_mse'], (int, float))
    assert np.isfinite(metrics['classification_accuracy'])
    assert np.isfinite(metrics['regression_mse'])
    np.testing.assert_allclose(
        metrics['classification_accuracy'], expected_accuracy, rtol=0, atol=1e-12
    )
    np.testing.assert_allclose(
        metrics['regression_mse'], expected_mse, rtol=1e-10, atol=1e-10
    )


def test_execute_and_validate_pipeline():
    for name in ['generate_data.py', 'ingest.py', 'pipeline.py', 'test_repro.sh']:
        path = os.path.join(HOME, name)
        assert os.path.isfile(path), f'{path} is not a regular file.'

    run(['python3', '/home/user/generate_data.py'])

    expected = canonical_data()
    generated_train = pd.read_csv('/home/user/train.csv')
    generated_test = pd.read_csv('/home/user/test.csv')
    assert list(generated_train.columns) == list(expected.columns)
    assert list(generated_test.columns) == list(expected.columns)
    assert_frame_matches(generated_train, expected.iloc[:4000])
    assert_frame_matches(generated_test, expected.iloc[4000:])

    run(['python3', '/home/user/ingest.py'])
    con = duckdb.connect('/home/user/ml_data.duckdb', read_only=True)
    try:
        tables = {row[0] for row in con.execute('SHOW TABLES').fetchall()}
        assert 'train_data' in tables
        assert 'test_data' in tables
        train = con.execute('SELECT * FROM train_data ORDER BY id').fetchdf()
        test = con.execute('SELECT * FROM test_data ORDER BY id').fetchdf()
    finally:
        con.close()

    assert list(train.columns) == list(expected.columns)
    assert list(test.columns) == list(expected.columns)
    assert_frame_matches(train, expected.iloc[:4000])
    assert_frame_matches(test, expected.iloc[4000:])

    run(['python3', '/home/user/pipeline.py'])
    validate_outputs(train, test)
    with open('/home/user/predictions.csv', 'rb') as f:
        first_predictions = f.read()
    first_md5 = hashlib.md5(first_predictions).hexdigest()

    run(['python3', '/home/user/pipeline.py'])
    validate_outputs(train, test)
    with open('/home/user/predictions.csv', 'rb') as f:
        second_predictions = f.read()
    second_md5 = hashlib.md5(second_predictions).hexdigest()
    assert first_md5 == second_md5, 'pipeline.py did not produce reproducible predictions.'

    run(['bash', '/home/user/test_repro.sh'])
    validate_outputs(train, test)


def test_duckdb_exists():
    db_path = '/home/user/ml_data.duckdb'
    assert os.path.exists(db_path), f'{db_path} does not exist.'
    assert os.path.getsize(db_path) > 0, f'{db_path} is empty.'


def test_repro_status():
    status_path = '/home/user/repro_status.txt'
    assert os.path.exists(status_path), f'{status_path} does not exist.'
    with open(status_path, 'r') as f:
        content = f.read().strip()
    assert content == 'REPRODUCIBLE', f'Expected REPRODUCIBLE in {status_path}, got {content}'


def test_predictions_csv():
    preds_path = '/home/user/predictions.csv'
    assert os.path.exists(preds_path), f'{preds_path} does not exist.'
    with open(preds_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['id', 'class_pred', 'score_pred'], f'Incorrect columns in predictions.csv: {header}'
        row_count = sum(1 for row in reader)
        assert row_count == 1000, f'Expected 1000 prediction rows, got {row_count}'


def test_metrics_json():
    metrics_path = '/home/user/metrics.json'
    assert os.path.exists(metrics_path), f'{metrics_path} does not exist.'
    with open(metrics_path, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            assert False, f'{metrics_path} is not valid JSON.'
    assert 'classification_accuracy' in metrics, 'Missing classification_accuracy in metrics.json'
    assert 'regression_mse' in metrics, 'Missing regression_mse in metrics.json'
    assert isinstance(metrics['classification_accuracy'], (int, float)), 'classification_accuracy must be a number'
    assert isinstance(metrics['regression_mse'], (int, float)), 'regression_mse must be a number'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
