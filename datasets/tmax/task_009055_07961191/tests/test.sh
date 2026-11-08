#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import io
import os
import runpy
import secrets
import sys

import numpy as np
import pandas as pd
import sklearn.model_selection as model_selection
import sklearn.naive_bayes as naive_bayes
import sklearn.preprocessing as preprocessing
from sklearn.metrics import accuracy_score

ORIGINAL_SPLIT = model_selection.train_test_split
ORIGINAL_SCALER = preprocessing.StandardScaler
ORIGINAL_GNB = naive_bayes.GaussianNB


def snapshot(value):
    return np.array(value, copy=True)


def same_data(left, right):
    left = np.asarray(left)
    right = np.asarray(right)
    return left.shape == right.shape and np.allclose(left, right, equal_nan=True)


def expected_output(seed):
    df = pd.read_csv('/home/user/raw_data.csv')
    X = df[['feature1', 'feature2']]
    y = df['target']
    X_train, X_test, y_train, y_test = ORIGINAL_SPLIT(
        X, y, test_size=0.2, random_state=seed
    )
    scaler = ORIGINAL_SCALER()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)
    clf = ORIGINAL_GNB()
    clf.fit(X_train_scaled, y_train)
    accuracy = accuracy_score(y_test, clf.predict(X_test_scaled))
    return [
        f'Accuracy: {accuracy:.4f}',
        f'Class 1 Prior: {clf.class_prior_[1]:.4f}',
    ]


def run_instrumented(seed):
    state = {
        'events': [],
        'splits': [],
        'scaler_fits': [],
        'scaler_transforms': [],
        'models': [],
    }

    def checked_split(*args, **kwargs):
        state['events'].append('split')
        test_size = kwargs.get('test_size', args[2] if len(args) > 2 else None)
        random_state = kwargs.get('random_state', args[3] if len(args) > 3 else None)
        result = ORIGINAL_SPLIT(*args, **kwargs)
        state['splits'].append({
            'test_size': test_size,
            'random_state': random_state,
            'X_train': snapshot(result[0]),
            'X_test': snapshot(result[1]),
            'y_train': snapshot(result[2]),
            'y_test': snapshot(result[3]),
        })
        return result

    class CheckedScaler(ORIGINAL_SCALER):
        def __init__(self, *, copy=True, with_mean=True, with_std=True):
            super().__init__(copy=copy, with_mean=with_mean, with_std=with_std)

        def fit(self, X, y=None, sample_weight=None):
            state['events'].append('scaler_fit')
            state['scaler_fits'].append(snapshot(X))
            return super().fit(X, y=y, sample_weight=sample_weight)

        def transform(self, X, copy=None):
            input_data = snapshot(X)
            output = super().transform(X, copy=copy)
            state['scaler_transforms'].append((input_data, snapshot(output)))
            return output

    class CheckedGNB(ORIGINAL_GNB):
        def __init__(self, *, priors=None, var_smoothing=1e-9):
            super().__init__(priors=priors, var_smoothing=var_smoothing)
            self._record = {'fit_X': None, 'fit_y': None, 'predict_X': None}
            state['models'].append(self._record)

        def fit(self, X, y, sample_weight=None):
            self._record['fit_X'] = snapshot(X)
            self._record['fit_y'] = snapshot(y)
            return super().fit(X, y, sample_weight=sample_weight)

        def predict(self, X):
            self._record['predict_X'] = snapshot(X)
            return super().predict(X)

    model_selection.train_test_split = checked_split
    preprocessing.StandardScaler = CheckedScaler
    naive_bayes.GaussianNB = CheckedGNB
    old_argv = sys.argv[:]
    stdout = io.StringIO()
    try:
        sys.argv = ['/home/user/pipeline.py', str(seed)]
        with contextlib.redirect_stdout(stdout):
            runpy.run_path('/home/user/pipeline.py', run_name='__main__')
    finally:
        sys.argv = old_argv
        model_selection.train_test_split = ORIGINAL_SPLIT
        preprocessing.StandardScaler = ORIGINAL_SCALER
        naive_bayes.GaussianNB = ORIGINAL_GNB

    lines = stdout.getvalue().splitlines()
    assert lines == expected_output(seed), (
        f'Pipeline output for seed {seed} was {lines}, expected {expected_output(seed)}'
    )

    assert len(state['splits']) == 1, 'Pipeline must perform one train/test split.'
    split = state['splits'][0]
    assert split['test_size'] == 0.2, 'train_test_split must use test_size=0.2.'
    assert split['random_state'] == seed, 'The command-line seed must be passed as random_state.'

    assert len(state['scaler_fits']) == 1, 'StandardScaler must be fitted exactly once.'
    assert state['events'].index('split') < state['events'].index('scaler_fit'), (
        'StandardScaler was fitted before the train/test split.'
    )
    assert same_data(state['scaler_fits'][0], split['X_train']), (
        'StandardScaler must be fitted only on X_train.'
    )

    train_scaled = None
    test_scaled = None
    for transform_input, transform_output in state['scaler_transforms']:
        if same_data(transform_input, split['X_train']):
            train_scaled = transform_output
        if same_data(transform_input, split['X_test']):
            test_scaled = transform_output
    assert train_scaled is not None, 'The fitted scaler must transform X_train.'
    assert test_scaled is not None, 'The fitted scaler must transform X_test.'

    assert len(state['models']) == 1, 'The pipeline must use one GaussianNB model.'
    model = state['models'][0]
    assert model['fit_X'] is not None and same_data(model['fit_X'], train_scaled), (
        'GaussianNB must be fitted on the scaled training features.'
    )
    assert same_data(model['fit_y'], split['y_train']), 'GaussianNB must be fitted on y_train.'
    assert model['predict_X'] is not None and same_data(model['predict_X'], test_scaled), (
        'GaussianNB predictions must use the scaled test features.'
    )
    return lines


def test_results_file():
    results_path = '/home/user/results.txt'
    assert os.path.isfile(results_path), f"{results_path} does not exist."

    with open(results_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {results_path}, found {len(lines)}."
    assert lines[0] == "Accuracy: 0.8800", f"Line 1 incorrect. Expected 'Accuracy: 0.8800', got '{lines[0]}'"
    assert lines[1] == "Class 1 Prior: 0.3062", f"Line 2 incorrect. Expected 'Class 1 Prior: 0.3062', got '{lines[1]}'"


def test_pipeline_script_fixed():
    script_path = '/home/user/pipeline.py'
    assert os.path.isfile(script_path), f"{script_path} does not exist."

    with open(script_path, 'r') as f:
        code = f.read()

    # Preserve the original source-order assertions.
    tts_idx = code.find('train_test_split(')
    assert tts_idx != -1, "train_test_split() not found in pipeline.py"

    fit_idx = code.find('fit_transform(')
    assert fit_idx != -1, "fit_transform() not found in pipeline.py"

    assert tts_idx < fit_idx, "Data leakage bug not fixed: train_test_split must be called before fit_transform."

    seed_42_lines = run_instrumented(42)
    with open('/home/user/results.txt', 'r') as f:
        saved_lines = [line.strip() for line in f if line.strip()]
    assert saved_lines == seed_42_lines, 'results.txt must contain the output produced for seed 42.'

    other_seed = secrets.randbelow(2_000_000_000) + 1
    if other_seed == 42:
        other_seed = 43
    run_instrumented(other_seed)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
