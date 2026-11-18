#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os

import joblib
import numpy as np
import pandas as pd
import pytest
from sklearn.decomposition import TruncatedSVD
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.utils.validation import check_is_fitted

PIPELINE_PATH = '/home/user/output/pipeline.pkl'
METRICS_PATH = '/home/user/output/metrics.json'
DATA_PATH = '/home/user/data/raw_texts.csv'


def load_submission():
    try:
        return joblib.load(PIPELINE_PATH)
    except Exception as exc:
        pytest.fail(f'Unable to load {PIPELINE_PATH} with joblib: {exc}')


def load_metrics():
    with open(METRICS_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{METRICS_PATH} does not contain valid JSON.')


def specified_split():
    data = pd.read_csv(DATA_PATH)
    return train_test_split(
        data['text'],
        data['category'],
        test_size=0.2,
        random_state=42,
        stratify=data['category'],
    )


def test_pipeline_saved():
    assert os.path.exists(PIPELINE_PATH), f'{PIPELINE_PATH} is missing.'
    assert os.path.isfile(PIPELINE_PATH), f'{PIPELINE_PATH} is not a file.'
    assert os.path.getsize(PIPELINE_PATH) > 0, f'{PIPELINE_PATH} is empty.'


def test_metrics_saved():
    assert os.path.exists(METRICS_PATH), f'{METRICS_PATH} is missing.'
    assert os.path.isfile(METRICS_PATH), f'{METRICS_PATH} is not a file.'

    metrics = load_metrics()
    assert 'accuracy' in metrics, "The key 'accuracy' is missing in metrics.json."
    accuracy = metrics['accuracy']
    assert isinstance(accuracy, (float, int)), "The 'accuracy' value is not a number."
    assert 0.0 <= accuracy <= 1.0, f"The 'accuracy' value {accuracy} is out of bounds [0.0, 1.0]."


def test_pipeline_structure_parameters_and_fitted_behavior():
    submitted = load_submission()
    assert isinstance(submitted, Pipeline), 'pipeline.pkl must contain a scikit-learn Pipeline.'
    assert len(submitted.steps) == 3, 'The Pipeline must contain exactly three steps.'

    vectorizer = submitted.steps[0][1]
    svd = submitted.steps[1][1]
    model = submitted.steps[2][1]

    assert isinstance(vectorizer, TfidfVectorizer), 'The first Pipeline step must be TfidfVectorizer.'
    assert vectorizer.max_features == 500, 'TfidfVectorizer must use max_features=500.'
    assert isinstance(svd, TruncatedSVD), 'The second Pipeline step must be TruncatedSVD.'
    assert svd.n_components == 50, 'TruncatedSVD must use n_components=50.'
    assert svd.random_state == 42, 'TruncatedSVD must use random_state=42.'
    assert isinstance(model, LogisticRegression), 'The third Pipeline step must be LogisticRegression.'
    assert model.random_state == 42, 'LogisticRegression must use random_state=42.'

    for component in (vectorizer, svd, model):
        try:
            check_is_fitted(component)
        except Exception as exc:
            pytest.fail(f'A Pipeline component is not fitted: {exc}')

    X_train, X_test, y_train, y_test = specified_split()

    reference = Pipeline([
        ('embedding', TfidfVectorizer(max_features=500)),
        ('dimensionality_reduction', TruncatedSVD(n_components=50, random_state=42)),
        ('model_training', LogisticRegression(random_state=42)),
    ])
    reference.fit(X_train, y_train)
    expected_predictions = reference.predict(X_test)

    try:
        submitted_predictions = submitted.predict(X_test)
    except Exception as exc:
        pytest.fail(f'The saved Pipeline cannot predict the specified test split: {exc}')

    assert np.array_equal(submitted_predictions, expected_predictions), (
        'The saved Pipeline predictions do not match a Pipeline trained on the specified 80/20 split.'
    )

    recomputed_accuracy = float(accuracy_score(y_test, submitted_predictions))
    reported_accuracy = load_metrics()['accuracy']
    assert abs(float(reported_accuracy) - recomputed_accuracy) <= 1e-12, (
        f'metrics.json reports accuracy {reported_accuracy}, but the saved Pipeline achieves '
        f'{recomputed_accuracy} on the specified test split.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
