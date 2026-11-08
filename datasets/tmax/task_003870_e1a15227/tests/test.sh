#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import io
import os
import re
import runpy

import joblib
import numpy as np
import pandas as pd
import pytest
from sklearn.model_selection import train_test_split as real_train_test_split
from sklearn.neural_network import MLPClassifier
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

SCRIPT = '/home/user/train_and_benchmark.py'
MODEL = '/home/user/solution_pipeline.joblib'
DATA_DIR = '/home/user/data'


def test_complete_workflow():
    assert os.path.isfile(SCRIPT), f'Missing required script: {SCRIPT}'

    if os.path.exists(MODEL):
        os.remove(MODEL)

    events = {'reads': [], 'splits': [], 'predicts': {}, 'dumps': []}

    real_read_csv = pd.read_csv
    real_split = real_train_test_split
    real_predict = Pipeline.predict
    real_dump = joblib.dump

    def monitored_read_csv(path, *args, **kwargs):
        try:
            events['reads'].append(os.path.realpath(os.fspath(path)))
        except TypeError:
            pass
        return real_read_csv(path, *args, **kwargs)

    def monitored_split(*arrays, **kwargs):
        result = real_split(*arrays, **kwargs)
        events['splits'].append({
            'arrays': [a.copy() if hasattr(a, 'copy') else np.array(a, copy=True) for a in arrays],
            'kwargs': dict(kwargs),
            'result': [a.copy() if hasattr(a, 'copy') else np.array(a, copy=True) for a in result],
        })
        return result

    def monitored_predict(self, X, *args, **kwargs):
        key = id(self)
        event = events['predicts'].setdefault(key, {'count': 0, 'first_X': None, 'consistent': True})
        current = np.asarray(X).copy()
        if event['first_X'] is None:
            event['first_X'] = current
        elif event['first_X'].shape != current.shape or not np.allclose(event['first_X'], current):
            event['consistent'] = False
        event['count'] += 1
        return real_predict(self, X, *args, **kwargs)

    def monitored_dump(value, filename, *args, **kwargs):
        path = os.path.realpath(os.fspath(filename))
        events['dumps'].append((id(value), path))
        return real_dump(value, filename, *args, **kwargs)

    pd.read_csv = monitored_read_csv
    import sklearn.model_selection
    sklearn.model_selection.train_test_split = monitored_split
    Pipeline.predict = monitored_predict
    joblib.dump = monitored_dump

    output = io.StringIO()
    try:
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            runpy.run_path(SCRIPT, run_name='__main__')
    finally:
        pd.read_csv = real_read_csv
        sklearn.model_selection.train_test_split = real_split
        Pipeline.predict = real_predict
        joblib.dump = real_dump

    assert os.path.isfile(MODEL), (
        'The file /home/user/solution_pipeline.joblib is missing. '
        'Did the script save the fitted Pipeline?'
    )

    required_reads = {
        os.path.realpath(os.path.join(DATA_DIR, 'features_A.csv')),
        os.path.realpath(os.path.join(DATA_DIR, 'features_B.csv')),
        os.path.realpath(os.path.join(DATA_DIR, 'labels.csv')),
    }
    assert required_reads.issubset(set(events['reads'])), 'The script must read all three supplied CSV files.'

    matching_splits = []
    for event in events['splits']:
        if len(event['arrays']) < 2:
            continue
        X_in, y_in = event['arrays'][:2]
        if np.shape(X_in) == (2000, 20) and np.shape(y_in)[0] == 2000:
            matching_splits.append(event)
    assert matching_splits, 'The joined 20-feature dataset was not passed to train_test_split.'
    split_event = matching_splits[-1]
    assert split_event['kwargs'].get('test_size') == 0.2, 'train_test_split must use test_size=0.2.'
    assert split_event['kwargs'].get('random_state') == 42, 'train_test_split must use random_state=42.'

    A = real_read_csv(os.path.join(DATA_DIR, 'features_A.csv'))
    B = real_read_csv(os.path.join(DATA_DIR, 'features_B.csv'))
    labels = real_read_csv(os.path.join(DATA_DIR, 'labels.csv'))
    joined = A.merge(B, on='uuid', how='inner').merge(labels, on='uuid', how='inner')
    expected_columns = [c for c in joined.columns if c not in ('uuid', 'label')]

    X_supplied, y_supplied = split_event['arrays'][:2]
    if isinstance(X_supplied, pd.DataFrame):
        supplied_columns = list(X_supplied.columns)
        assert set(supplied_columns) == set(expected_columns), 'Split features do not match the inner-joined CSV features.'
        expected_X = joined[supplied_columns]
    else:
        supplied_columns = expected_columns
        expected_X = joined[expected_columns]
    assert np.allclose(np.asarray(X_supplied), np.asarray(expected_X)), 'The split input is not the inner-joined feature data.'
    assert np.array_equal(np.asarray(y_supplied).reshape(-1), joined['label'].to_numpy()), 'The split labels do not match labels.csv.'

    X_train, X_test, y_train, y_test = split_event['result'][:4]
    assert len(X_train) == 1600 and len(X_test) == 400, 'The workflow must perform an 80/20 split.'

    model_dumps = [obj_id for obj_id, path in events['dumps'] if path == os.path.realpath(MODEL)]
    assert model_dumps, 'The script must save the Pipeline with joblib.dump.'
    dumped_id = model_dumps[-1]
    benchmark = events['predicts'].get(dumped_id)
    assert benchmark is not None, 'The saved Pipeline was not used for the inference benchmark.'
    assert benchmark['count'] == 100, f"Expected exactly 100 predict calls in the benchmark, got {benchmark['count']}."
    assert benchmark['consistent'], 'All benchmark predict calls must use the same test set.'
    assert benchmark['first_X'].shape == np.asarray(X_test).shape
    assert np.allclose(benchmark['first_X'], np.asarray(X_test)), 'The benchmark must call predict on the test set.'

    printed = output.getvalue()
    assert re.search(r'average[^\n]*inference[^\n]*\d+(?:\.\d+)?[^\n]*(?:ms|milliseconds)', printed, re.I), (
        'The script must print the average inference time in milliseconds.'
    )

    try:
        pipeline = joblib.load(MODEL)
    except Exception as exc:
        pytest.fail(f'Failed to load the pipeline from {MODEL}: {exc}')

    assert hasattr(pipeline, 'steps'), 'The saved object is not a scikit-learn Pipeline.'
    assert isinstance(pipeline, Pipeline), 'The saved object is not a scikit-learn Pipeline.'
    assert len(pipeline.steps) >= 2, 'The pipeline should have at least a scaler and a classifier.'

    scaler = pipeline.steps[0][1]
    mlp = pipeline.steps[-1][1]
    assert type(scaler).__name__ == 'StandardScaler', 'The first step of the pipeline is not a StandardScaler.'
    assert type(mlp).__name__ == 'MLPClassifier', 'The last step of the pipeline is not an MLPClassifier.'
    assert isinstance(mlp, MLPClassifier)

    assert mlp.hidden_layer_sizes == (128, 64), f'Expected hidden_layer_sizes=(128, 64), got {mlp.hidden_layer_sizes}'
    assert mlp.activation == 'relu', f"Expected activation='relu', got {mlp.activation}"
    assert mlp.alpha == 0.05, f'Expected alpha=0.05, got {mlp.alpha}'
    assert mlp.random_state == 42, f'Expected random_state=42, got {mlp.random_state}'
    assert mlp.max_iter == 500, f'Expected max_iter=500, got {mlp.max_iter}'

    expected_mean = np.asarray(X_train, dtype=float).mean(axis=0)
    expected_var = np.asarray(X_train, dtype=float).var(axis=0)
    assert np.allclose(scaler.mean_, expected_mean), 'StandardScaler was not fitted exclusively on the training split.'
    assert np.allclose(scaler.var_, expected_var), 'StandardScaler statistics do not match the training split.'
    assert np.all(np.asarray(scaler.n_samples_seen_) == len(X_train)), 'Scaler sample count does not match the training split.'

    accuracy = pipeline.score(X_test, y_test)
    threshold = 0.80
    assert accuracy >= threshold, (
        f'Pipeline accuracy on the held-out 20% of the supplied dataset is {accuracy:.4f}, '
        f'which is below the required threshold of {threshold:.4f}.'
    )
TEST_EOF

if timeout 240 python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
