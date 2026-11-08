#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import joblib
import numpy as np
import pandas as pd
import pytest
from sklearn.base import clone
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import KFold, cross_val_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.utils.validation import check_is_fitted

METRICS_PATH = '/home/user/metrics.jsonl'
MODEL_PATH = '/home/user/best_model.pkl'
DATA_PATH = '/home/user/raw_data.csv'

# Independently derive the required engineered data and expected results.
df = pd.read_csv(DATA_PATH)
assert list(df.columns) == ['f0', 'f1', 'f2', 'f3', 'f4', 'target']
X_ENGINEERED = df[['f0', 'f1', 'f2', 'f3', 'f4']].copy()
X_ENGINEERED['f5'] = X_ENGINEERED['f0'] * X_ENGINEERED['f1']
y = df['target'].to_numpy()

EXPECTED_SCALER = StandardScaler()
X_SCALED = EXPECTED_SCALER.fit_transform(X_ENGINEERED)
CV = KFold(n_splits=5, shuffle=True, random_state=42)

EXPECTED_MODELS = {
    'LogisticRegression': LogisticRegression(C=1.0, random_state=42),
    'RandomForestClassifier': RandomForestClassifier(
        n_estimators=50, max_depth=5, random_state=42
    ),
}
EXPECTED_HYPERPARAMETERS = {
    'LogisticRegression': {'C': 1.0, 'random_state': 42},
    'RandomForestClassifier': {
        'n_estimators': 50, 'max_depth': 5, 'random_state': 42
    },
}
EXPECTED_ACCURACIES = {
    name: float(cross_val_score(model, X_SCALED, y, cv=CV, scoring='accuracy').mean())
    for name, model in EXPECTED_MODELS.items()
}
EXPECTED_BEST_NAME = max(EXPECTED_ACCURACIES, key=EXPECTED_ACCURACIES.get)
EXPECTED_FINAL_MODEL = clone(EXPECTED_MODELS[EXPECTED_BEST_NAME]).fit(X_SCALED, y)


def test_metrics_file_exists():
    assert os.path.exists(METRICS_PATH), f'Metrics file not found at {METRICS_PATH}'
    assert os.path.isfile(METRICS_PATH), f'{METRICS_PATH} is not a file'


def test_metrics_content():
    assert os.path.exists(METRICS_PATH), 'Metrics file missing'

    with open(METRICS_PATH, 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 2, f'Expected exactly 2 lines in metrics.jsonl, found {len(lines)}'

    models_logged = []
    accuracies = {}

    for line in lines:
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f'Invalid JSON line in metrics.jsonl: {line}')

        assert set(data) == {'model_name', 'mean_cv_accuracy', 'hyperparameters'}, \
            f'JSON object has incorrect schema: {data}'
        assert 'model_name' in data, "Missing 'model_name' in JSON"
        assert 'mean_cv_accuracy' in data, "Missing 'mean_cv_accuracy' in JSON"
        assert 'hyperparameters' in data, "Missing 'hyperparameters' in JSON"

        name = data['model_name']
        models_logged.append(name)
        accuracies[name] = data['mean_cv_accuracy']

        assert name in EXPECTED_HYPERPARAMETERS, f'Unexpected model name: {name}'
        assert data['hyperparameters'] == EXPECTED_HYPERPARAMETERS[name], \
            f'Incorrect hyperparameters for {name}: {data["hyperparameters"]}'
        assert isinstance(data['mean_cv_accuracy'], float), f'{name} accuracy must be a float'
        assert np.isclose(
            data['mean_cv_accuracy'], EXPECTED_ACCURACIES[name], rtol=0, atol=1e-12
        ), f'Incorrect cross-validation accuracy for {name}: expected {EXPECTED_ACCURACIES[name]}, got {data["mean_cv_accuracy"]}'

    assert set(models_logged) == {'LogisticRegression', 'RandomForestClassifier'}, \
        f'Expected models LogisticRegression and RandomForestClassifier, got {models_logged}'

    lr_acc = accuracies.get('LogisticRegression')
    rf_acc = accuracies.get('RandomForestClassifier')
    assert isinstance(lr_acc, float), 'LogisticRegression accuracy must be a float'
    assert isinstance(rf_acc, float), 'RandomForestClassifier accuracy must be a float'
    assert 0.80 < lr_acc < 0.90, f'LogisticRegression accuracy out of expected bounds (0.80-0.90): {lr_acc}'
    assert 0.85 < rf_acc < 0.95, f'RandomForestClassifier accuracy out of expected bounds (0.85-0.95): {rf_acc}'


def test_best_model_exists():
    assert os.path.exists(MODEL_PATH), f'Best model file not found at {MODEL_PATH}'
    assert os.path.isfile(MODEL_PATH), f'{MODEL_PATH} is not a file'


def test_best_model_is_fitted_correct_model_and_predicts_correctly():
    assert os.path.exists(MODEL_PATH), 'Best model file missing'

    try:
        best_model = joblib.load(MODEL_PATH)
    except Exception as e:
        pytest.fail(f'Failed to load best_model.pkl: {e}')

    model_type = type(best_model).__name__
    final_model = best_model
    prediction_input = X_SCALED

    if model_type == 'Pipeline':
        assert len(best_model.steps) >= 2, 'Saved pipeline has no preprocessing step'
        final_model = best_model.steps[-1][1]
        model_type = type(final_model).__name__
        assert any(
            isinstance(value, StandardScaler)
            for value in best_model.get_params(deep=True).values()
        ), 'Saved pipeline must contain a StandardScaler'
        prediction_input = X_ENGINEERED

    assert model_type == 'RandomForestClassifier', \
        f'Expected best model to be RandomForestClassifier (or a pipeline ending in it), got {model_type}'
    assert EXPECTED_BEST_NAME == 'RandomForestClassifier'
    assert isinstance(final_model, RandomForestClassifier)
    assert final_model.n_estimators == 50, 'RandomForestClassifier must use n_estimators=50'
    assert final_model.max_depth == 5, 'RandomForestClassifier must use max_depth=5'
    assert final_model.random_state == 42, 'RandomForestClassifier must use random_state=42'
    assert getattr(final_model, 'n_features_in_', None) == 6, 'Model must be fitted using features f0 through f5'

    try:
        check_is_fitted(best_model)
        actual_predictions = best_model.predict(prediction_input)
        actual_probabilities = best_model.predict_proba(prediction_input)
    except Exception as e:
        pytest.fail(f'Saved model is not fitted and executable: {e}')

    expected_predictions = EXPECTED_FINAL_MODEL.predict(X_SCALED)
    expected_probabilities = EXPECTED_FINAL_MODEL.predict_proba(X_SCALED)
    assert np.array_equal(actual_predictions, expected_predictions), \
        'Saved model predictions do not match the required full-data fit'
    assert np.allclose(actual_probabilities, expected_probabilities, rtol=0, atol=1e-12), \
        'Saved model probabilities do not match the required full-data fit'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
