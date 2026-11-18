#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import subprocess

import joblib
import numpy as np
import pandas as pd
import pytest
from sklearn.base import clone
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.model_selection import GridSearchCV
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.utils.validation import check_is_fitted

SCRIPT_PATH = '/home/user/train_pipeline.py'
PIPELINE_PATH = '/home/user/best_pipeline.pkl'
METRICS_PATH = '/home/user/metrics.json'
DATA_PATH = '/home/user/dataset.csv'


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT_PATH), f"Training script not found at {SCRIPT_PATH}."
    for path in (PIPELINE_PATH, METRICS_PATH):
        if os.path.lexists(path):
            if os.path.isdir(path):
                pytest.fail(f"Expected output path {path} is a directory.")
            os.unlink(path)

    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=300,
    )
    assert result.returncode == 0, f"Training script failed:\n{result.stdout}"


def load_metrics():
    with open(METRICS_PATH, 'r') as f:
        return json.load(f)


def canonical_search():
    df = pd.read_csv(DATA_PATH)
    X = df.drop(columns=['is_promoted'])
    y = df['is_promoted']

    numeric = Pipeline([
        ('imputer', SimpleImputer(strategy='mean')),
        ('scaler', StandardScaler()),
    ])
    categorical = Pipeline([
        ('imputer', SimpleImputer(strategy='constant', fill_value='missing')),
        ('encoder', OneHotEncoder(handle_unknown='ignore')),
    ])
    preprocessing = ColumnTransformer([
        ('numeric', numeric, ['age', 'training_score', 'years_of_service']),
        ('categorical', categorical, ['department', 'education']),
    ])
    pipeline = Pipeline([
        ('preprocessor', preprocessing),
        ('classifier', RandomForestClassifier(random_state=42)),
    ])
    search = GridSearchCV(
        pipeline,
        {
            'classifier__n_estimators': [10, 50],
            'classifier__max_depth': [5, None],
        },
        cv=3,
    )
    search.fit(X, y)
    return X, y, search


def find_required_transformers(column_transformer):
    found = {}
    active = []
    for name, transformer, columns in column_transformer.transformers:
        if transformer == 'drop':
            continue
        active.append((name, transformer, list(columns)))
        column_set = set(columns)
        if column_set == {'age', 'training_score', 'years_of_service'}:
            assert list(columns) == ['age', 'training_score', 'years_of_service']
            found['numeric'] = transformer
        elif column_set == {'department', 'education'}:
            assert list(columns) == ['department', 'education']
            found['categorical'] = transformer
        else:
            pytest.fail(f"Unexpected active ColumnTransformer columns: {list(columns)}")
    assert len(active) == 2, "ColumnTransformer must contain exactly the required numeric and categorical branches."
    assert set(found) == {'numeric', 'categorical'}
    return found


def test_pipeline_saved():
    """Verify that the best pipeline was saved as a file."""
    pipeline_path = '/home/user/best_pipeline.pkl'
    assert os.path.exists(pipeline_path), f"Pipeline file not found at {pipeline_path}."
    assert os.path.isfile(pipeline_path), f"{pipeline_path} is not a regular file."
    assert os.path.getsize(pipeline_path) > 0, f"Pipeline file at {pipeline_path} is empty."


def test_metrics_json_saved_and_valid():
    """Verify that metrics.json exists and contains the correct structure."""
    metrics_path = '/home/user/metrics.json'
    assert os.path.exists(metrics_path), f"Metrics file not found at {metrics_path}."
    assert os.path.isfile(metrics_path), f"{metrics_path} is not a regular file."

    with open(metrics_path, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {metrics_path} does not contain valid JSON.")

    assert "best_cv_score" in metrics, "Missing 'best_cv_score' key in metrics.json."
    assert "best_params" in metrics, "Missing 'best_params' key in metrics.json."

    score = metrics["best_cv_score"]
    assert isinstance(score, (float, int)), "best_cv_score must be a numeric value."
    assert 0.0 <= score <= 1.0, f"best_cv_score ({score}) is out of expected bounds [0.0, 1.0]."

    params = metrics["best_params"]
    assert isinstance(params, dict), "best_params must be a dictionary object."

    keys_str = str(params.keys())
    assert "n_estimators" in keys_str, "n_estimators parameter is missing from best_params."
    assert "max_depth" in keys_str, "max_depth parameter is missing from best_params."


def test_saved_object_is_fitted_required_pipeline():
    model = joblib.load(PIPELINE_PATH)
    assert isinstance(model, Pipeline), "Saved object must be a scikit-learn Pipeline."
    assert len(model.steps) >= 2

    classifier_name, classifier = model.steps[-1]
    assert isinstance(classifier, RandomForestClassifier), "Final estimator must be RandomForestClassifier."
    assert classifier.random_state == 42, "RandomForestClassifier random_state must be 42."
    check_is_fitted(classifier)

    transformers = [step for _, step in model.steps[:-1] if isinstance(step, ColumnTransformer)]
    assert len(transformers) == 1, "Pipeline must contain one ColumnTransformer before the classifier."
    preprocessor = transformers[0]
    check_is_fitted(preprocessor)
    assert preprocessor.remainder == 'drop'

    branches = find_required_transformers(preprocessor)
    numeric = branches['numeric']
    categorical = branches['categorical']
    assert isinstance(numeric, Pipeline)
    assert isinstance(categorical, Pipeline)
    assert len(numeric.steps) == 2
    assert len(categorical.steps) == 2

    numeric_imputer = numeric.steps[0][1]
    scaler = numeric.steps[1][1]
    categorical_imputer = categorical.steps[0][1]
    encoder = categorical.steps[1][1]

    assert isinstance(numeric_imputer, SimpleImputer)
    assert numeric_imputer.strategy == 'mean'
    assert isinstance(scaler, StandardScaler)
    assert isinstance(categorical_imputer, SimpleImputer)
    assert categorical_imputer.strategy == 'constant'
    assert categorical_imputer.fill_value == 'missing'
    assert isinstance(encoder, OneHotEncoder)
    assert encoder.handle_unknown == 'ignore'
    check_is_fitted(model)


def test_metrics_and_model_match_real_grid_search():
    model = joblib.load(PIPELINE_PATH)
    metrics = load_metrics()
    X, _, expected = canonical_search()

    classifier_name, classifier = model.steps[-1]
    expected_semantic = {
        'n_estimators': expected.best_params_['classifier__n_estimators'],
        'max_depth': expected.best_params_['classifier__max_depth'],
    }
    expected_params = {
        f'{classifier_name}__n_estimators': expected_semantic['n_estimators'],
        f'{classifier_name}__max_depth': expected_semantic['max_depth'],
    }

    assert set(metrics.keys()) == {'best_cv_score', 'best_params'}
    assert metrics['best_params'] == expected_params
    assert np.isclose(float(metrics['best_cv_score']), expected.best_score_, rtol=0, atol=1e-12)
    assert classifier.n_estimators == expected_semantic['n_estimators']
    assert classifier.max_depth == expected_semantic['max_depth']

    submitted_ct = next(step for _, step in model.steps[:-1] if isinstance(step, ColumnTransformer))
    expected_ct = expected.best_estimator_.named_steps['preprocessor']
    submitted_features = submitted_ct.transform(X)
    expected_features = expected_ct.transform(X)
    if hasattr(submitted_features, 'toarray'):
        submitted_features = submitted_features.toarray()
    if hasattr(expected_features, 'toarray'):
        expected_features = expected_features.toarray()
    np.testing.assert_allclose(submitted_features, expected_features, rtol=1e-12, atol=1e-12)
    np.testing.assert_array_equal(model.predict(X), expected.best_estimator_.predict(X))
    np.testing.assert_allclose(model.predict_proba(X), expected.best_estimator_.predict_proba(X), rtol=1e-12, atol=1e-12)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
