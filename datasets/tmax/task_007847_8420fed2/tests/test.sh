#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import sys
import json
import math
import secrets
import subprocess

import numpy as np
import pandas as pd
import pyarrow.parquet as pq
import pytest
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error

PROJECT = '/home/user/project'
RAW = os.path.join(PROJECT, 'raw_features.csv')
PREPARE = os.path.join(PROJECT, 'prepare.py')
TRAIN = os.path.join(PROJECT, 'train.py')
PARQUET = os.path.join(PROJECT, 'processed.parquet')
METRICS = os.path.join(PROJECT, 'metrics.json')
REQUIRED_COLUMNS = ['id', 'user_id', 'click_count', 'time_spent', 'target']


def original_raw_dataframe():
    rs = np.random.RandomState(10)
    n = 1000
    id_col = np.arange(n)
    user_id = rs.randint(100, 500, size=n).astype(float)
    click_count = rs.randint(0, 50, size=n).astype(float)
    time_spent = rs.uniform(10.0, 100.0, size=n)
    target = 3.5 * click_count + 1.2 * time_spent + rs.normal(0, 5, size=n)
    user_id[rs.choice(n, 50, replace=False)] = np.nan
    click_count[rs.choice(n, 50, replace=False)] = np.nan
    df = pd.DataFrame({
        'id': id_col,
        'user_id': user_id,
        'click_count': click_count,
        'time_spent': time_spent,
        'target': target,
    })
    # Match the CSV serialization and parsing used during image setup.
    buffer = io.StringIO()
    df.to_csv(buffer, index=False)
    buffer.seek(0)
    return pd.read_csv(buffer)


def expected_processed(raw_df):
    df = raw_df.copy()
    assert list(df.columns) == REQUIRED_COLUMNS
    df['user_id'] = df['user_id'].fillna(-1).astype('int64')
    df['click_count'] = df['click_count'].fillna(-1).astype('int64')
    df['id'] = df['id'].astype('int64')
    df['time_spent'] = StandardScaler().fit_transform(df[['time_spent']])
    return df


def expected_mse(df):
    X = df[['user_id', 'click_count', 'time_spent']]
    y = df['target']
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, shuffle=False
    )
    model = Ridge(alpha=1.0, random_state=42)
    model.fit(X_train, y_train)
    return float(mean_squared_error(y_test, model.predict(X_test)))


def execute(script):
    result = subprocess.run(
        [sys.executable, script], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert result.returncode == 0, (
        f'{script} failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def validate_parquet(expected):
    assert os.path.isfile(PARQUET), f'{PARQUET} does not exist. Did prepare.py run successfully?'
    try:
        actual = pd.read_parquet(PARQUET)
    except Exception as exc:
        pytest.fail(f'Failed to read {PARQUET}. Is it a valid parquet file? Error: {exc}')

    assert list(actual.columns) == REQUIRED_COLUMNS, (
        f'Processed dataframe columns are {list(actual.columns)}, expected {REQUIRED_COLUMNS}'
    )
    assert len(actual) == len(expected), f'Expected {len(expected)} rows, got {len(actual)}'
    assert str(actual['id'].dtype) == 'int64', f"id column is not strictly int64, got {actual['id'].dtype}"
    assert str(actual['user_id'].dtype) == 'int64', f"user_id column is not strictly int64, got {actual['user_id'].dtype}"
    assert str(actual['click_count'].dtype) == 'int64', f"click_count column is not strictly int64, got {actual['click_count'].dtype}"
    assert actual['user_id'].isna().sum() == 0, 'user_id column still contains missing values (NaNs)'
    assert actual['click_count'].isna().sum() == 0, 'click_count column still contains missing values (NaNs)'
    pd.testing.assert_frame_equal(actual, expected, check_dtype=True, rtol=1e-10, atol=1e-10)

    parquet_file = pq.ParquetFile(PARQUET)
    assert parquet_file.metadata.num_rows == len(expected)
    assert parquet_file.metadata.num_row_groups > 0
    for row_group_index in range(parquet_file.metadata.num_row_groups):
        row_group = parquet_file.metadata.row_group(row_group_index)
        for column_index in range(row_group.num_columns):
            compression = row_group.column(column_index).compression
            assert compression == 'SNAPPY', (
                f'Parquet column {row_group.column(column_index).path_in_schema} '
                f'uses {compression}, expected SNAPPY'
            )
    return actual


def validate_metrics(processed):
    assert os.path.isfile(METRICS), f'{METRICS} does not exist. Did train.py run successfully?'
    try:
        with open(METRICS, 'r') as handle:
            metrics = json.load(handle)
    except json.JSONDecodeError:
        pytest.fail(f'{METRICS} does not contain valid JSON.')

    assert isinstance(metrics, dict), 'metrics.json must contain a JSON object'
    assert 'mse' in metrics, f"metrics.json must contain the key 'mse'. Got keys: {list(metrics.keys())}"
    assert set(metrics) == {'mse'}, f"metrics.json must contain only the 'mse' key. Got keys: {list(metrics.keys())}"
    actual = metrics['mse']
    assert isinstance(actual, (float, int)), f'MSE value must be a float, got {type(actual)}'
    assert not isinstance(actual, bool) and math.isfinite(float(actual)), 'MSE must be a finite number'
    expected = expected_mse(processed)
    assert math.isclose(float(actual), expected, rel_tol=1e-4, abs_tol=1e-4), (
        f'Computed MSE {actual} does not match the expected MSE {expected}.'
    )


def run_pipeline(raw_df):
    raw_df.to_csv(RAW, index=False)
    for output in (PARQUET, METRICS):
        if os.path.lexists(output):
            os.remove(output)
    execute(PREPARE)
    processed = validate_parquet(expected_processed(pd.read_csv(RAW)))
    execute(TRAIN)
    validate_metrics(processed)


@pytest.fixture(scope='session', autouse=True)
def execute_and_exercise_pipeline():
    assert os.path.isfile(PREPARE), 'prepare.py is missing from /home/user/project/'
    assert os.path.isfile(TRAIN), 'train.py is missing from /home/user/project/'
    assert os.path.getsize(PREPARE) > 0, 'prepare.py is empty'
    assert os.path.getsize(TRAIN) > 0, 'train.py is empty'
    assert os.path.isfile(RAW), f'Original data {RAW} is missing, cannot compute expected MSE.'

    original_bytes = open(RAW, 'rb').read()
    actual_original = pd.read_csv(RAW)
    pd.testing.assert_frame_equal(
        actual_original, original_raw_dataframe(), check_dtype=True, rtol=1e-12, atol=1e-12
    )

    try:
        run_pipeline(actual_original)

        # Exercise both scripts on an unpredictable valid dataset so fixed outputs
        # or a hard-coded MSE cannot satisfy the verifier.
        rng = np.random.default_rng(secrets.randbits(128))
        n = 53
        user = rng.integers(20, 900, size=n).astype(float)
        clicks = rng.integers(0, 100, size=n).astype(float)
        user[rng.choice(n, 7, replace=False)] = np.nan
        clicks[rng.choice(n, 8, replace=False)] = np.nan
        time = rng.uniform(-20.0, 250.0, size=n)
        target = rng.normal(0, 3, size=n) + 2.7 * np.nan_to_num(clicks, nan=-1) - 0.8 * time
        challenge = pd.DataFrame({
            'id': rng.choice(np.arange(10000, 50000), size=n, replace=False),
            'user_id': user,
            'click_count': clicks,
            'time_spent': time,
            'target': target,
        })
        run_pipeline(challenge)
    finally:
        with open(RAW, 'wb') as handle:
            handle.write(original_bytes)
        # Restore the requested final artifacts for the original input.
        try:
            run_pipeline(pd.read_csv(RAW))
        except Exception:
            pass


def test_scripts_exist():
    assert os.path.exists(PREPARE), 'prepare.py is missing from /home/user/project/'
    assert os.path.exists(TRAIN), 'train.py is missing from /home/user/project/'


def test_parquet_exists_and_types():
    validate_parquet(expected_processed(pd.read_csv(RAW)))


def test_metrics_json_and_mse():
    processed = validate_parquet(expected_processed(pd.read_csv(RAW)))
    validate_metrics(processed)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
