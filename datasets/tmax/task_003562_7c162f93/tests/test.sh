#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import runpy

import numpy as np
import pandas as pd
import sklearn.model_selection as model_selection
import sklearn.preprocessing as preprocessing

SCRIPT_FILE = '/home/user/clean_data.py'
DATASET_FILE = '/home/user/dataset.csv'
METRICS_FILE = '/home/user/metrics.json'


def arrays_equal(a, b):
    try:
        aa = np.asarray(a, dtype=float)
        bb = np.asarray(b, dtype=float)
        return aa.shape == bb.shape and np.allclose(aa, bb, rtol=1e-10, atol=1e-10)
    except Exception:
        return False


def run_and_check(df):
    df.to_csv(DATASET_FILE, index=False)

    real_split = model_selection.train_test_split
    real_scaler = preprocessing.StandardScaler
    events = []
    split_calls = []
    scaler_calls = []

    def tracked_split(*args, **kwargs):
        events.append('split')
        result = real_split(*args, **kwargs)
        split_calls.append((args, kwargs, result))
        return result

    class TrackedStandardScaler(real_scaler):
        def fit(self, X, y=None, sample_weight=None):
            events.append('fit')
            scaler_calls.append(('fit', id(self), np.asarray(X).copy()))
            if sample_weight is None:
                return super().fit(X, y)
            return super().fit(X, y, sample_weight=sample_weight)

        def transform(self, X, copy=None):
            events.append('transform')
            scaler_calls.append(('transform', id(self), np.asarray(X).copy()))
            return super().transform(X, copy=copy)

    model_selection.train_test_split = tracked_split
    preprocessing.StandardScaler = TrackedStandardScaler
    try:
        runpy.run_path(SCRIPT_FILE, run_name='__main__')
    finally:
        model_selection.train_test_split = real_split
        preprocessing.StandardScaler = real_scaler

    assert split_calls, 'clean_data.py did not call train_test_split.'
    assert scaler_calls, 'clean_data.py did not use StandardScaler.'
    assert 'split' in events and 'fit' in events
    assert events.index('split') < events.index('fit'), (
        'StandardScaler was fitted before train_test_split was called.'
    )

    matching_split = None
    for args, kwargs, result in split_calls:
        if not args:
            continue
        candidate = np.asarray(args[0])
        if candidate.ndim == 2 and candidate.shape == (len(df), 2):
            matching_split = (args, kwargs, result)
            break

    assert matching_split is not None, 'The feature data was not split with train_test_split.'
    args, kwargs, result = matching_split
    assert kwargs.get('test_size') == 0.2, 'train_test_split must use test_size=0.2.'
    assert kwargs.get('random_state') == 42, 'train_test_split must use random_state=42.'
    assert len(result) >= 2
    X_train, X_test = result[0], result[1]

    fit_calls = [call for call in scaler_calls if call[0] == 'fit']
    assert fit_calls, 'StandardScaler.fit was not called.'
    assert all(arrays_equal(call[2], X_train) for call in fit_calls), (
        'StandardScaler must be fitted only on the training features.'
    )

    valid_scaler = False
    for _, scaler_id, fit_input in fit_calls:
        transforms = [c[2] for c in scaler_calls if c[0] == 'transform' and c[1] == scaler_id]
        if (arrays_equal(fit_input, X_train)
                and any(arrays_equal(v, X_train) for v in transforms)
                and any(arrays_equal(v, X_test) for v in transforms)):
            valid_scaler = True
            break
    assert valid_scaler, (
        'The same training-fitted StandardScaler must transform both train and test features.'
    )

    assert os.path.exists(METRICS_FILE), f'{METRICS_FILE} does not exist after running the script.'
    with open(METRICS_FILE, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            assert False, f'{METRICS_FILE} contains invalid JSON.'
    assert 'test_feature1_mean' in metrics, "Key 'test_feature1_mean' not found in metrics.json."

    X = df[['feature1', 'feature2']]
    y = df['target']
    expected_train, expected_test, _, _ = real_split(
        X, y, test_size=0.2, random_state=42
    )
    expected_scaler = real_scaler()
    expected_scaler.fit(expected_train)
    expected = float(expected_scaler.transform(expected_test)[:, 0].mean())
    val = metrics['test_feature1_mean']
    assert isinstance(val, (int, float)) and not isinstance(val, bool)
    assert math.isclose(val, expected, rel_tol=1e-9, abs_tol=1e-8), (
        f'Expected test_feature1_mean to be approximately {expected}, but got {val}.'
    )
    return val


def canonical_dataset():
    np.random.seed(42)
    return pd.DataFrame({
        'feature1': np.random.normal(10, 5, 100),
        'feature2': np.random.normal(20, 2, 100),
        'target': np.random.randint(0, 2, 100),
    })


def test_clean_data_script_exists():
    assert os.path.exists(SCRIPT_FILE), f'{SCRIPT_FILE} does not exist.'
    assert os.path.isfile(SCRIPT_FILE), f'{SCRIPT_FILE} is not a file.'


def test_metrics_json_correct():
    assert os.path.exists(METRICS_FILE), f'{METRICS_FILE} does not exist. Did you run the script?'
    val = run_and_check(canonical_dataset())
    expected = -0.19833621453265008
    assert math.isclose(val, expected, abs_tol=1e-5), (
        f'Expected test_feature1_mean to be approx {expected}, but got {val}. '
        'Make sure you split the data FIRST, then fit the scaler ONLY on the training set.'
    )


def test_script_on_additional_dataset():
    rng = np.random.default_rng(734921)
    n = 137
    feature1 = rng.normal(-12, 3.5, n)
    feature2 = rng.normal(80, 11, n)
    feature1[[4, 29, 91, 120]] += np.array([150, -90, 220, -175])
    feature2[[8, 46, 103]] += np.array([-300, 410, -250])
    df = pd.DataFrame({
        'feature1': feature1,
        'feature2': feature2,
        'target': rng.integers(0, 2, n),
    })
    run_and_check(df)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
