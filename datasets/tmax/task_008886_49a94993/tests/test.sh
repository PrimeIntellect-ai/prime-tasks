#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import ast
import runpy
from functools import wraps

import pandas as pd
import pytest
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import GridSearchCV
from sklearn.pipeline import Pipeline


@pytest.fixture(scope="session", autouse=True)
def executed_submission():
    """Execute train.py and record how GridSearchCV is actually used."""
    train_path = "/home/user/train.py"
    results_path = "/home/user/results.json"
    assert os.path.isfile(train_path), f"File not found: {train_path}"

    if os.path.exists(results_path):
        os.remove(results_path)

    calls = []
    original_init = GridSearchCV.__init__
    original_fit = GridSearchCV.fit

    @wraps(original_init)
    def recording_init(self, estimator, param_grid, *args, **kwargs):
        original_init(self, estimator, param_grid, *args, **kwargs)
        calls.append({
            "object": self,
            "estimator": estimator,
            "param_grid": param_grid,
            "cv": self.cv,
            "fitted": False,
            "X": None,
            "y": None,
        })

    @wraps(original_fit)
    def recording_fit(self, X, y=None, *args, **kwargs):
        matching = next((call for call in reversed(calls) if call["object"] is self), None)
        if matching is not None:
            matching["fitted"] = True
            matching["X"] = X.tolist() if isinstance(X, pd.Series) else None
            matching["y"] = y.tolist() if isinstance(y, pd.Series) else None
        return original_fit(self, X, y, *args, **kwargs)

    GridSearchCV.__init__ = recording_init
    GridSearchCV.fit = recording_fit
    try:
        runpy.run_path(train_path, run_name="__main__")
    finally:
        GridSearchCV.__init__ = original_init
        GridSearchCV.fit = original_fit

    return calls


def test_results_json_exists():
    """Check if the results.json file was created by the executed script."""
    file_path = "/home/user/results.json"
    assert os.path.isfile(file_path), f"File not found: {file_path}. Did you run the script?"


def test_results_json_structure():
    """Check if the results.json has the correct structure and keys."""
    file_path = "/home/user/results.json"
    with open(file_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, "results.json is not a valid JSON file."

    assert "best_score" in results, "'best_score' key missing from results.json"
    assert "best_params" in results, "'best_params' key missing from results.json"

    best_params = results["best_params"]
    assert isinstance(best_params, dict), "'best_params' should be a dictionary"
    assert "clf__C" in best_params, "'clf__C' missing from best_params"
    assert "tfidf__max_features" in best_params, "'tfidf__max_features' missing from best_params"

    assert isinstance(results["best_score"], float), "'best_score' should be a float"
    assert best_params["clf__C"] in [0.1, 1.0], "'clf__C' should be one of the grid search values"
    assert best_params["tfidf__max_features"] in [10, 50], "'tfidf__max_features' should be one of the grid search values"


def test_train_py_uses_pipeline():
    """Check if train.py was updated to use a Pipeline and correct grid search params."""
    file_path = "/home/user/train.py"
    assert os.path.isfile(file_path), f"File not found: {file_path}"

    with open(file_path, 'r') as f:
        content = f.read()

    assert "Pipeline" in content, "train.py does not seem to use a scikit-learn Pipeline."
    assert "tfidf__max_features" in content, "train.py does not tune 'tfidf__max_features'."
    assert "clf__C" in content, "train.py does not tune 'clf__C'."

    content_no_spaces = content.replace(" ", "")
    assert "cv=3" in content_no_spaces, "train.py does not seem to use cv=3 in GridSearchCV."


def test_train_py_no_data_leakage():
    """Ensure that fit_transform is not explicitly called before GridSearchCV."""
    file_path = "/home/user/train.py"
    with open(file_path, 'r') as f:
        try:
            tree = ast.parse(f.read())
        except SyntaxError:
            assert False, "train.py contains a syntax error."

    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            assert node.func.attr != 'fit_transform', \
                "train.py explicitly calls fit_transform; TF-IDF must be fitted inside the Pipeline."


def test_runtime_grid_search_configuration(executed_submission):
    """Verify that execution fits the required pipeline on the raw dataset."""
    df = pd.read_csv('/home/user/reviews.csv')
    expected_x = df['text'].tolist()
    expected_y = df['sentiment'].tolist()

    valid_calls = []
    for call in executed_submission:
        estimator = call["estimator"]
        if not isinstance(estimator, Pipeline):
            continue
        if list(estimator.named_steps.keys()) != ['tfidf', 'clf']:
            continue
        if not isinstance(estimator.named_steps['tfidf'], TfidfVectorizer):
            continue
        if not isinstance(estimator.named_steps['clf'], LogisticRegression):
            continue
        if estimator.named_steps['clf'].random_state != 42:
            continue
        if call["cv"] != 3 or not call["fitted"]:
            continue
        if call["X"] != expected_x or call["y"] != expected_y:
            continue
        grid = call["param_grid"]
        if not isinstance(grid, dict) or set(grid) != {'tfidf__max_features', 'clf__C'}:
            continue
        if list(grid['tfidf__max_features']) != [10, 50]:
            continue
        if list(grid['clf__C']) != [0.1, 1.0]:
            continue
        valid_calls.append(call)

    assert valid_calls, (
        "train.py did not fit GridSearchCV(cv=3) on raw text using the required "
        "tfidf/clf Pipeline and exact parameter grid."
    )


def test_results_match_recomputed_grid_search():
    """Independently recompute the requested search and compare its result."""
    df = pd.read_csv('/home/user/reviews.csv')
    reference_pipeline = Pipeline([
        ('tfidf', TfidfVectorizer()),
        ('clf', LogisticRegression(random_state=42)),
    ])
    reference_grid = GridSearchCV(
        reference_pipeline,
        {
            'tfidf__max_features': [10, 50],
            'clf__C': [0.1, 1.0],
        },
        cv=3,
    )
    reference_grid.fit(df['text'], df['sentiment'])

    with open('/home/user/results.json', 'r') as f:
        results = json.load(f)

    assert results['best_params'] == reference_grid.best_params_, \
        "best_params does not match the requested grid search on reviews.csv"
    assert abs(results['best_score'] - float(reference_grid.best_score_)) < 1e-12, \
        "best_score does not match the requested grid search on reviews.csv"
TEST_EOF

if timeout 180s python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
