#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import runpy
import subprocess
from unittest.mock import patch

import numpy as np
import pytest
from sklearn.feature_selection import SelectKBest, f_regression
from sklearn.linear_model import Ridge
from sklearn.model_selection import KFold, cross_val_score
from sklearn.pipeline import Pipeline

SCRIPT_PATH = '/home/user/model_pipeline.py'
METRICS_PATH = '/home/user/metrics.json'


def expected_data_and_score():
    np.random.seed(42)
    X = np.random.randn(100, 1000)
    y = np.random.randn(100)
    estimator = Pipeline([
        ('selector', SelectKBest(score_func=f_regression, k=10)),
        ('model', Ridge()),
    ])
    cv = KFold(n_splits=5, shuffle=True, random_state=42)
    score = cross_val_score(estimator, X, y, cv=cv, scoring='r2').mean()
    return X, y, float(score)


def test_script_executes_and_metrics_json_exists_and_correct():
    """Execute the submission and check its reported score against an independent computation."""
    assert os.path.isfile(SCRIPT_PATH), f"File not found: {SCRIPT_PATH}"
    if os.path.exists(METRICS_PATH):
        os.remove(METRICS_PATH)

    completed = subprocess.run(
        ['python3', SCRIPT_PATH], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert completed.returncode == 0, (
        f"The script failed when executed.\nstdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )

    assert os.path.isfile(METRICS_PATH), f"File not found: {METRICS_PATH}. Did you run the script?"
    with open(METRICS_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {METRICS_PATH} does not contain valid JSON.")

    assert "mean_r2" in data, "metrics.json must contain the key 'mean_r2'."
    assert set(data) == {'mean_r2'}, "metrics.json must contain the single key 'mean_r2'."
    r2 = data["mean_r2"]
    assert isinstance(r2, (int, float)), "mean_r2 must be a number."

    # Preserve the original score assertions.
    assert r2 < 0.0, f"Expected negative R2 due to noise data without leakage, got {r2}. Data leakage might still be present."
    assert abs(r2 - (-0.1989)) < 0.05, f"Expected R2 around -0.1989, got {r2}. Did you use the correct model, k, and CV strategy?"

    _, _, expected = expected_data_and_score()
    assert np.isclose(r2, expected, rtol=0, atol=1e-12), (
        f"mean_r2 was {r2}, but independently executing the required non-leaky "
        f"pipeline gives {expected}."
    )


def test_pipeline_used_in_script():
    """Preserve the original source check for Pipeline usage."""
    assert os.path.isfile(SCRIPT_PATH), f"File not found: {SCRIPT_PATH}"
    with open(SCRIPT_PATH, 'r') as f:
        content = f.read()
    assert 'Pipeline' in content or 'make_pipeline' in content, (
        "The script must use a Pipeline (or make_pipeline) from sklearn.pipeline to prevent data leakage."
    )


def test_cross_validation_really_receives_required_pipeline_and_metric_is_derived():
    """Probe execution so comments or a hardcoded metric cannot satisfy the verifier."""
    expected_X, expected_y, _ = expected_data_and_score()
    calls = []
    sentinel_scores = np.array([-0.11, -0.22, -0.33, -0.44, -0.55])

    def fake_cross_val_score(estimator, X, y, *args, **kwargs):
        calls.append((estimator, np.array(X), np.array(y), args, kwargs))
        return sentinel_scores.copy()

    with open(METRICS_PATH, 'rb') as f:
        original_metrics = f.read()

    try:
        with patch('sklearn.model_selection.cross_val_score', side_effect=fake_cross_val_score):
            runpy.run_path(SCRIPT_PATH, run_name='__main__')
        with open(METRICS_PATH, 'r') as f:
            probed_metrics = json.load(f)
    finally:
        with open(METRICS_PATH, 'wb') as f:
            f.write(original_metrics)

    assert len(calls) == 1, "The script must call sklearn.model_selection.cross_val_score exactly once."
    estimator, X, y, args, kwargs = calls[0]
    assert isinstance(estimator, Pipeline), "cross_val_score must receive a sklearn Pipeline."
    assert len(estimator.steps) == 2, "The Pipeline must contain SelectKBest followed by Ridge."
    assert isinstance(estimator.steps[0][1], SelectKBest), "The first Pipeline step must be SelectKBest."
    assert estimator.steps[0][1].k == 10, "SelectKBest must use k=10."
    assert estimator.steps[0][1].score_func is f_regression, "SelectKBest must use f_regression."
    assert isinstance(estimator.steps[1][1], Ridge), "The final Pipeline step must be Ridge."

    cv = kwargs.get('cv', args[0] if args else None)
    scoring = kwargs.get('scoring', args[1] if len(args) > 1 else None)
    assert isinstance(cv, KFold), "Cross-validation must use KFold."
    assert cv.n_splits == 5, "KFold must use 5 splits."
    assert cv.shuffle is True, "KFold must use shuffle=True."
    assert cv.random_state == 42, "KFold must use random_state=42."
    assert scoring == 'r2', "Cross-validation must use R2 scoring."

    assert np.array_equal(X, expected_X), "The data generation section or X passed to CV was modified."
    assert np.array_equal(y, expected_y), "The data generation section or y passed to CV was modified."
    assert set(probed_metrics) == {'mean_r2'}, "metrics.json must contain only mean_r2."
    assert np.isclose(probed_metrics['mean_r2'], sentinel_scores.mean(), rtol=0, atol=1e-15), (
        "metrics.json mean_r2 must be computed from the cross_val_score results, not hardcoded."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
