#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import math
import os
import re
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, f1_score
from sklearn.model_selection import train_test_split

RAW_CSV = """user_id,age,event_code,session_duration,is_fraud
1,22,4,120.5,0
2,35,2,,0
3,42,,300.2,1
4,19,4,45.0,0
5,28,1,150.0,0
6,50,,500.5,1
7,24,2,90.0,0
8,31,4,110.0,0
9,45,1,,1
10,21,2,80.0,0
11,36,,400.0,1
12,29,4,130.0,0
13,18,1,60.0,0
14,55,2,200.0,0
15,23,,450.0,1
16,33,4,140.0,0
17,27,1,160.0,0
18,48,2,,1
19,20,4,75.0,0
20,38,1,190.0,0
"""


def expected_raw():
    return pd.read_csv(io.StringIO(RAW_CSV))


def assert_raw_is_original():
    actual = pd.read_csv('/home/user/raw_events.csv')
    pd.testing.assert_frame_equal(actual, expected_raw(), check_dtype=False)


def binary_values(series, name):
    values = []
    for value in series:
        text = str(value).strip().lower()
        if text == 'true':
            values.append(1)
        elif text == 'false':
            values.append(0)
        else:
            try:
                number = float(text)
            except ValueError:
                pytest.fail(f"Column {name} contains a non-binary value: {value!r}")
            assert number in (0.0, 1.0), f"Column {name} contains a non-binary value: {value!r}"
            values.append(int(number))
    return np.asarray(values, dtype=int)


def canonical_metrics():
    frame = expected_raw()
    frame['session_duration'] = frame['session_duration'].fillna(frame['session_duration'].median())
    frame['event_code'] = frame['event_code'].fillna(-1).astype(int)
    frame['is_youth'] = (frame['age'] < 25).astype(int)
    dummies = pd.get_dummies(frame['event_code'], prefix='event_code', dtype=int)
    frame = pd.concat([frame.drop(columns=['event_code']), dummies], axis=1)

    dummy_columns = [f'event_code_{code}' for code in sorted([-1, 1, 2, 4])]
    features = ['age', 'session_duration', 'is_youth'] + dummy_columns
    X_train, X_test, y_train, y_test = train_test_split(
        frame[features], frame['is_fraud'], test_size=0.25, random_state=42
    )
    model = LogisticRegression(random_state=42, max_iter=1000)
    model.fit(X_train, y_train)
    predictions = model.predict(X_test)
    return {
        'accuracy': accuracy_score(y_test, predictions),
        'f1_score': f1_score(y_test, predictions, average='binary'),
    }


def test_pipeline_and_outputs():
    pipeline_path = '/home/user/pipeline.py'
    assert os.path.isfile(pipeline_path), f'The file {pipeline_path} does not exist.'
    assert os.path.getsize(pipeline_path) > 0, f'The file {pipeline_path} is empty.'
    assert_raw_is_original()

    for output in ('/home/user/processed_events.csv', '/home/user/metrics.json'):
        if os.path.lexists(output):
            os.remove(output)

    result = subprocess.run(
        [sys.executable, pipeline_path],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'pipeline.py exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert_raw_is_original()

    metrics_path = '/home/user/metrics.json'
    assert os.path.isfile(metrics_path), f'The file {metrics_path} does not exist.'
    with open(metrics_path, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{metrics_path} is not a valid JSON file.')

    assert 'accuracy' in metrics, f"'accuracy' key missing in {metrics_path}."
    assert 'f1_score' in metrics, f"'f1_score' key missing in {metrics_path}."
    assert isinstance(metrics['accuracy'], (int, float)), "'accuracy' must be a number."
    assert isinstance(metrics['f1_score'], (int, float)), "'f1_score' must be a number."
    assert set(metrics) == {'accuracy', 'f1_score'}, 'metrics.json must contain exactly the required keys.'

    expected_metrics = canonical_metrics()
    for key in ('accuracy', 'f1_score'):
        assert math.isfinite(metrics[key]), f'{key} must be finite.'
        assert 0 <= metrics[key] <= 1, f'{key} must be between 0 and 1.'
        assert metrics[key] == pytest.approx(expected_metrics[key], abs=1e-12), (
            f'{key} was not produced by the required train/test split and model.'
        )

    processed_path = '/home/user/processed_events.csv'
    assert os.path.isfile(processed_path), f'The file {processed_path} does not exist.'
    with open(processed_path, 'r', newline='') as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail(f'{processed_path} is empty.')

        assert 'is_youth' in headers, "Column 'is_youth' is missing from the processed CSV."
        assert any(h.startswith('event_code_-1') and not h.startswith('event_code_-1.0') for h in headers), \
            'event_code_-1 not found or formatted as float (e.g., event_code_-1.0).'
        assert any(h.startswith('event_code_4') and not h.startswith('event_code_4.0') for h in headers), \
            'event_code_4 not found or formatted as float (e.g., event_code_4.0).'
        assert 'session_duration' in headers, "Column 'session_duration' is missing."
        session_duration_idx = headers.index('session_duration')
        rows = list(reader)
        for row_num, row in enumerate(rows, start=2):
            if len(row) > session_duration_idx:
                val = row[session_duration_idx].strip()
                assert val != '', f'Missing session_duration value found in row {row_num}.'
        assert len(rows) == 20, 'processed_events.csv must contain all 20 input records.'

    processed = pd.read_csv(processed_path)
    assert len(processed) == 20, 'processed_events.csv must contain all 20 input records.'
    assert not any(str(c).startswith('Unnamed:') for c in processed.columns), \
        'processed_events.csv must not include a saved dataframe index.'

    required_base = {'user_id', 'age', 'session_duration', 'is_fraud', 'is_youth'}
    assert required_base.issubset(processed.columns), 'Processed CSV is missing required columns.'
    assert processed['user_id'].is_unique, 'Each input record must appear exactly once.'

    processed = processed.sort_values('user_id').reset_index(drop=True)
    raw = expected_raw().sort_values('user_id').reset_index(drop=True)
    for column in ('user_id', 'age', 'is_fraud'):
        actual = pd.to_numeric(processed[column], errors='raise').to_numpy()
        expected = raw[column].to_numpy()
        assert np.array_equal(actual, expected), f'Column {column} does not match the input data.'

    expected_duration = raw['session_duration'].fillna(raw['session_duration'].median()).to_numpy()
    actual_duration = pd.to_numeric(processed['session_duration'], errors='raise').to_numpy()
    assert np.isfinite(actual_duration).all(), 'session_duration contains missing or non-finite values.'
    assert np.allclose(actual_duration, expected_duration, rtol=0, atol=1e-12), \
        'session_duration was not imputed with the dataset median.'

    expected_youth = (raw['age'] < 25).astype(int).to_numpy()
    actual_youth = binary_values(processed['is_youth'], 'is_youth')
    assert np.array_equal(actual_youth, expected_youth), 'is_youth was calculated incorrectly.'

    expected_dummy_columns = {'event_code_-1', 'event_code_1', 'event_code_2', 'event_code_4'}
    actual_dummy_columns = {
        str(c) for c in processed.columns if re.fullmatch(r'event_code_.+', str(c))
    }
    assert actual_dummy_columns == expected_dummy_columns, \
        'One-hot event_code columns are missing, extra, or have float suffixes.'

    event_codes = raw['event_code'].fillna(-1).astype(int).to_numpy()
    for code in (-1, 1, 2, 4):
        column = f'event_code_{code}'
        actual = binary_values(processed[column], column)
        expected = (event_codes == code).astype(int)
        assert np.array_equal(actual, expected), f'Column {column} is encoded incorrectly.'

    dummy_matrix = np.column_stack([
        binary_values(processed[f'event_code_{code}'], f'event_code_{code}')
        for code in (-1, 1, 2, 4)
    ])
    assert np.all(dummy_matrix.sum(axis=1) == 1), 'Each row must have exactly one event_code indicator.'

    if 'event_code' in processed.columns:
        retained_codes = pd.to_numeric(processed['event_code'], errors='raise').to_numpy()
        assert np.isfinite(retained_codes).all(), 'Retained event_code contains missing values.'
        assert np.all(retained_codes == np.floor(retained_codes)), 'Retained event_code must be integer-valued.'
        assert np.array_equal(retained_codes.astype(int), event_codes), 'Retained event_code values are incorrect.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
