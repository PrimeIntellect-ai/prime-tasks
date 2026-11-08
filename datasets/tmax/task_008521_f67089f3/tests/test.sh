#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import inspect
import json
import os
import subprocess
import sys
import types

import numpy as np
import pandas as pd
import pytest


def test_test_pipeline_exists_and_passes():
    path = '/home/user/test_pipeline.py'
    assert os.path.isfile(path), f"Expected test file at {path} is missing."

    result = subprocess.run([sys.executable, '-m', 'pytest', path], capture_output=True, text=True)
    assert result.returncode == 0, f"pytest failed on {path}:\n{result.stdout}\n{result.stderr}"

    with open(path, 'r') as f:
        content = f.read()
    assert 'def test_no_float_cast' in content, 'test_no_float_cast function is missing from test_pipeline.py'


def _run_submitted_test_with_dtype(dtype, module_name):
    calls = {'load': 0, 'clean': 0}
    fake_pipeline = types.ModuleType('pipeline')

    def load_data():
        calls['load'] += 1
        return pd.DataFrame({
            'user_id': pd.Series([1000000000000001, 1000000000000002], dtype='Int64'),
            'feature_1': [0.0, -1.5],
            'feature_2': [1.0, 2.0],
            'target': [0, 1],
        })

    def clean_data(df):
        calls['clean'] += 1
        result = df.copy()
        if dtype == 'Int64':
            result['user_id'] = result['user_id'].astype('Int64')
        else:
            result['user_id'] = result['user_id'].astype('float64')
        return result

    fake_pipeline.load_data = load_data
    fake_pipeline.clean_data = clean_data

    previous = sys.modules.get('pipeline')
    sys.modules['pipeline'] = fake_pipeline
    try:
        spec = importlib.util.spec_from_file_location(module_name, '/home/user/test_pipeline.py')
        submitted = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(submitted)
        assert hasattr(submitted, 'test_no_float_cast'), 'test_no_float_cast function is missing from test_pipeline.py'
        submitted.test_no_float_cast()
    finally:
        if previous is None:
            sys.modules.pop('pipeline', None)
        else:
            sys.modules['pipeline'] = previous
    return calls


def test_submitted_test_actually_checks_dtype():
    calls = _run_submitted_test_with_dtype('Int64', 'submitted_test_good')
    assert calls['load'] > 0, 'test_no_float_cast must call load_data()'
    assert calls['clean'] > 0, 'test_no_float_cast must call clean_data()'

    with pytest.raises(AssertionError):
        _run_submitted_test_with_dtype('float64', 'submitted_test_bad')


def test_experiment_results_json():
    path = '/home/user/experiment_results.json'
    assert os.path.isfile(path), f"Expected results file at {path} is missing."

    with open(path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('experiment_results.json is not a valid JSON file.')

    assert 'best_params' in results, "Key 'best_params' missing from experiment_results.json"
    assert 'learning_rate' in results['best_params'], "Key 'learning_rate' missing from best_params"
    assert 'max_iter' in results['best_params'], "Key 'max_iter' missing from best_params"
    assert 'best_score' in results, "Key 'best_score' missing from experiment_results.json"
    assert isinstance(results['best_score'], float), 'best_score must be a float'
    assert 0.0 <= results['best_score'] <= 1.0, 'best_score must be between 0.0 and 1.0'


def test_clean_data_logic():
    sys.path.insert(0, '/home/user')
    try:
        from pipeline import load_data, clean_data
    except ImportError as e:
        pytest.fail(f'Could not import load_data or clean_data from pipeline.py: {e}')

    df = load_data()
    df_clean = clean_data(df)
    assert str(df_clean['user_id'].dtype) == 'Int64', f"Expected Int64 dtype for user_id, got {df_clean['user_id'].dtype}"

    missing_mask = df_clean['user_id'].isna()
    expected_missing = df_clean['feature_1'] < -1.0
    assert (missing_mask == expected_missing).all(), 'Missing values in user_id do not match the expected condition (feature_1 < -1.0).'


def test_pipeline_train_and_evaluate_logic():
    path = '/home/user/pipeline.py'
    with open(path, 'r') as f:
        content = f.read()

    assert 'GridSearchCV' in content, 'GridSearchCV is missing from pipeline.py'
    assert 'cv=3' in content.replace(' ', ''), 'cv=3 is missing from GridSearchCV call'
    assert 'random_state=42' in content, 'random_state=42 is missing'
    assert 'HistGradientBoostingClassifier' in content, 'HistGradientBoostingClassifier is missing'


def test_train_and_evaluate_executes_required_grid_search():
    sys.path.insert(0, '/home/user')
    import pipeline
    from sklearn.ensemble import HistGradientBoostingClassifier
    from sklearn.model_selection import GridSearchCV as RealGridSearchCV

    rng = np.random.RandomState(8675309)
    n =  ninety = 90
    feature_1 = rng.normal(size=n)
    feature_2 = rng.uniform(-2.0, 3.0, size=n)
    target = ((feature_1 * 1.4 + feature_2 * 0.35 + rng.normal(scale=0.9, size=n)) > 0).astype(int)
    user_ids = pd.Series(1000000000000000 + np.arange(n) * 17, dtype='Int64')
    user_ids.iloc[::13] = pd.NA
    df = pd.DataFrame({
        'user_id': user_ids,
        'feature_1': feature_1,
        'feature_2': feature_2,
        'target': target,
    })

    records = []

    def recording_grid_search(*args, **kwargs):
        bound = inspect.signature(RealGridSearchCV).bind(*args, **kwargs)
        bound.apply_defaults()
        records.append(bound.arguments.copy())
        return RealGridSearchCV(*args, **kwargs)

    patched_names = []
    for name, value in list(vars(pipeline).items()):
        if value is RealGridSearchCV:
            patched_names.append(name)
            setattr(pipeline, name, recording_grid_search)

    import sklearn.model_selection
    original_sklearn_grid = sklearn.model_selection.GridSearchCV
    sklearn.model_selection.GridSearchCV = recording_grid_search

    results_path = '/home/user/experiment_results.json'
    if os.path.exists(results_path):
        os.remove(results_path)

    try:
        pipeline.train_and_evaluate(df.copy())
    finally:
        sklearn.model_selection.GridSearchCV = original_sklearn_grid
        for name in patched_names:
            setattr(pipeline, name, RealGridSearchCV)

    assert records, 'train_and_evaluate did not instantiate GridSearchCV'
    call = records[-1]
    assert call['cv'] == 3, f"Expected cv=3, got {call['cv']}"
    assert call['param_grid'] == {
        'max_iter': [50, 100],
        'learning_rate': [0.05, 0.1],
    }, f"Unexpected parameter grid: {call['param_grid']}"
    assert isinstance(call['estimator'], HistGradientBoostingClassifier), 'GridSearchCV must use HistGradientBoostingClassifier'
    assert call['estimator'].random_state == 42, 'HistGradientBoostingClassifier must use random_state=42'

    assert os.path.isfile(results_path), 'train_and_evaluate did not create experiment_results.json'
    with open(results_path, 'r') as f:
        actual = json.load(f)

    expected_search = RealGridSearchCV(
        HistGradientBoostingClassifier(random_state=42),
        {
            'max_iter': [50, 100],
            'learning_rate': [0.05, 0.1],
        },
        cv=3,
    )
    expected_search.fit(df[['user_id', 'feature_1', 'feature_2']], df['target'])

    assert set(actual.keys()) == {'best_params', 'best_score'}, 'experiment_results.json must have the exact required top-level keys'
    assert set(actual['best_params'].keys()) == {'learning_rate', 'max_iter'}, 'best_params must have the exact required keys'
    assert actual['best_params'] == expected_search.best_params_, 'Saved best_params do not match the executed grid search'
    assert isinstance(actual['best_params']['learning_rate'], float), 'learning_rate must be a float'
    assert isinstance(actual['best_params']['max_iter'], int), 'max_iter must be an int'
    assert isinstance(actual['best_score'], float), 'best_score must be a float'
    assert actual['best_score'] == pytest.approx(float(expected_search.best_score_), abs=1e-12), 'Saved best_score does not match the executed grid search'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
