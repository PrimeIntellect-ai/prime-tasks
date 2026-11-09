#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import numbers

import cv2
import numpy as np
import pandas as pd
import pytest
import requests
from sklearn.linear_model import Ridge
from sklearn.model_selection import cross_val_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

FEATURES_PATH = '/home/user/features.csv'
TARGETS_PATH = '/app/targets.csv'
VIDEO_PATH = '/app/experiment.mp4'
LOG_PATH = '/home/user/experiment_log.json'


def extract_expected_features():
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f'Could not open {VIDEO_PATH}.'

    rows = []
    frame_index = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        rows.append((frame_index, float(np.mean(gray)), float(np.std(gray))))
        frame_index += 1
    cap.release()

    assert len(rows) == 300, f'Expected 300 decoded video frames, found {len(rows)}.'
    return pd.DataFrame(rows, columns=['frame_index', 'mean_brightness', 'std_brightness'])


@pytest.fixture(scope='session')
def expected_features():
    return extract_expected_features()


@pytest.fixture(scope='session')
def merged_expected(expected_features):
    assert os.path.isfile(TARGETS_PATH), f'{TARGETS_PATH} is missing.'
    targets = pd.read_csv(TARGETS_PATH)
    assert {'frame_index', 'target_value'}.issubset(targets.columns)
    merged = pd.merge(expected_features, targets, on='frame_index', validate='one_to_one')
    assert len(merged) == 300, f'Expected 300 merged rows, found {len(merged)}.'
    return merged


def make_pipeline():
    return Pipeline([
        ('scaler', StandardScaler()),
        ('ridge', Ridge(alpha=1.0)),
    ])


def test_features_csv_exists_and_valid(expected_features):
    assert os.path.isfile(FEATURES_PATH), f'{FEATURES_PATH} is missing.'
    df = pd.read_csv(FEATURES_PATH)
    expected_columns = {'frame_index', 'mean_brightness', 'std_brightness'}
    assert expected_columns.issubset(df.columns), (
        f'Columns in {FEATURES_PATH} do not match expected. Found: {list(df.columns)}'
    )
    assert len(df) > 0, f'{FEATURES_PATH} is empty.'

    assert list(df.columns) == ['frame_index', 'mean_brightness', 'std_brightness'], (
        'features.csv must contain exactly the requested columns in the requested order.'
    )
    assert len(df) == 300, f'Expected one row for each of 300 frames, found {len(df)}.'

    frame_indices = pd.to_numeric(df['frame_index'], errors='coerce').to_numpy()
    means = pd.to_numeric(df['mean_brightness'], errors='coerce').to_numpy(dtype=float)
    stds = pd.to_numeric(df['std_brightness'], errors='coerce').to_numpy(dtype=float)
    assert np.all(np.isfinite(frame_indices)), 'frame_index contains non-numeric values.'
    assert np.array_equal(frame_indices, np.arange(300)), 'frame_index must run from 0 through 299 in order.'
    assert np.all(np.isfinite(means)), 'mean_brightness contains non-finite values.'
    assert np.all(np.isfinite(stds)), 'std_brightness contains non-finite values.'
    assert np.allclose(means, expected_features['mean_brightness'].to_numpy(), rtol=0, atol=1e-7), (
        'mean_brightness values do not match statistics recomputed from experiment.mp4.'
    )
    assert np.allclose(stds, expected_features['std_brightness'].to_numpy(), rtol=0, atol=1e-7), (
        'std_brightness values do not match statistics recomputed from experiment.mp4.'
    )


def test_experiment_log_exists_and_valid(merged_expected):
    assert os.path.isfile(LOG_PATH), f'{LOG_PATH} is missing.'
    with open(LOG_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{LOG_PATH} is not valid JSON.')

    assert 'cv_nmse' in data, f"'cv_nmse' key missing in {LOG_PATH}."
    assert isinstance(data['cv_nmse'], numbers.Real) and not isinstance(data['cv_nmse'], bool), (
        "'cv_nmse' must be a number."
    )
    assert np.isfinite(float(data['cv_nmse'])), "'cv_nmse' must be finite."

    X = merged_expected[['mean_brightness', 'std_brightness']]
    y = merged_expected['target_value']
    expected_cv_nmse = cross_val_score(
        make_pipeline(), X, y, cv=5, scoring='neg_mean_squared_error'
    ).mean()
    assert np.isclose(float(data['cv_nmse']), expected_cv_nmse, rtol=1e-8, atol=1e-6), (
        f'Logged cv_nmse {data["cv_nmse"]} does not match leakage-free 5-fold '
        f'pipeline CV result {expected_cv_nmse}.'
    )


def test_prediction_endpoint(merged_expected):
    assert os.path.isfile(FEATURES_PATH), f'{FEATURES_PATH} is missing.'
    assert os.path.isfile(TARGETS_PATH), f'{TARGETS_PATH} is missing.'

    # Preserve the original merged-data validity assertion while relying on the
    # separately verified frame statistics for the prediction oracle.
    features_df = pd.read_csv(FEATURES_PATH)
    targets_df = pd.read_csv(TARGETS_PATH)
    merged_df = pd.merge(features_df, targets_df, on='frame_index')
    assert len(merged_df) > 0, 'Merged dataset is empty.'

    X = merged_expected[['mean_brightness', 'std_brightness']]
    y = merged_expected['target_value']
    pipeline = make_pipeline()
    pipeline.fit(X, y)

    test_cases = [
        {'mean_brightness': 100.5, 'std_brightness': 25.0},
        {'mean_brightness': 50.0, 'std_brightness': 10.0},
        {'mean_brightness': 200.0, 'std_brightness': 50.0},
    ]
    rng = np.random.default_rng()
    for _ in range(5):
        test_cases.append({
            'mean_brightness': float(rng.uniform(0.0, 255.0)),
            'std_brightness': float(rng.uniform(0.0, 80.0)),
        })

    url = 'http://127.0.0.1:8080/predict'
    for payload in test_cases:
        try:
            response = requests.post(url, json=payload, timeout=5)
        except requests.exceptions.RequestException as exc:
            pytest.fail(f'Failed to connect to {url}: {exc}')

        assert response.status_code == 200, (
            f'Expected HTTP 200, got {response.status_code}. Response: {response.text}'
        )
        try:
            resp_json = response.json()
        except ValueError:
            pytest.fail(f'Response is not valid JSON: {response.text}')

        assert 'prediction' in resp_json, f"'prediction' key missing in response: {resp_json}"
        pred_val = resp_json['prediction']
        assert isinstance(pred_val, numbers.Real) and not isinstance(pred_val, bool), (
            f'Prediction must be a number, got {type(pred_val)}'
        )
        assert np.isfinite(float(pred_val)), 'Prediction must be finite.'

        expected_pred = pipeline.predict(pd.DataFrame([payload]))[0]
        assert abs(float(pred_val) - expected_pred) < 1e-3, (
            f'Expected prediction ~{expected_pred:.4f}, but got {pred_val} for payload {payload}'
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
