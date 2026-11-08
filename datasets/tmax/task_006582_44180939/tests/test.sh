#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import time
from functools import lru_cache

import joblib
import numpy as np
import pandas as pd
from sklearn.linear_model import ElasticNet
from sklearn.model_selection import GridSearchCV

HISTORICAL_PATH = "/home/user/historical_data.csv"
BATCH_PATH = "/home/user/new_batch.csv"
MODEL_PATH = "/home/user/best_model.pkl"
RESULTS_PATH = "/home/user/pipeline_results.json"
FEATURES = ["x1", "x2", "x3", "x4", "x5"]


@lru_cache(maxsize=1)
def reference_results():
    historical = pd.read_csv(HISTORICAL_PATH)
    batch = pd.read_csv(BATCH_PATH)

    assert list(historical.columns) == FEATURES + ["y"]
    assert list(batch.columns) == FEATURES

    search = GridSearchCV(
        ElasticNet(random_state=42),
        {
            "alpha": [0.1, 1.0, 10.0],
            "l1_ratio": [0.1, 0.5, 0.9],
        },
        cv=5,
    )
    search.fit(historical[FEATURES], historical["y"])
    predictions = search.best_estimator_.predict(batch[FEATURES])
    return search, predictions, batch


def load_submitted_model():
    try:
        return joblib.load(MODEL_PATH)
    except Exception as exc:
        raise AssertionError(f"Saved model could not be loaded: {exc}") from exc


def test_model_persistence():
    model_path = MODEL_PATH
    assert os.path.isfile(model_path), f"Missing saved model file: {model_path}"
    assert os.path.getsize(model_path) > 0, f"Saved model file {model_path} is empty"

    model = load_submitted_model()
    assert isinstance(model, ElasticNet), (
        f"Saved artifact must be a fitted sklearn ElasticNet, got {type(model).__name__}"
    )
    assert hasattr(model, "coef_") and hasattr(model, "intercept_"), "Saved ElasticNet is not fitted"
    assert model.random_state == 42, f"ElasticNet random_state must be 42, got {model.random_state}"

    search, expected_predictions, batch = reference_results()
    reference_model = search.best_estimator_
    assert math.isclose(float(model.alpha), float(reference_model.alpha), abs_tol=1e-12)
    assert math.isclose(float(model.l1_ratio), float(reference_model.l1_ratio), abs_tol=1e-12)
    np.testing.assert_allclose(model.coef_, reference_model.coef_, rtol=1e-9, atol=1e-10)
    np.testing.assert_allclose(model.intercept_, reference_model.intercept_, rtol=1e-9, atol=1e-10)

    start = time.perf_counter()
    actual_predictions = model.predict(batch[FEATURES])
    measured_time = time.perf_counter() - start
    assert measured_time > 0.0 and math.isfinite(measured_time)
    assert actual_predictions.shape == expected_predictions.shape
    np.testing.assert_allclose(actual_predictions, expected_predictions, rtol=1e-9, atol=1e-9)


def test_pipeline_results_json():
    results_path = RESULTS_PATH
    assert os.path.isfile(results_path), f"Missing results JSON file: {results_path}"

    with open(results_path, 'r') as f:
        try:
            res = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {results_path} is not valid JSON"

    required_keys = {
        "best_alpha",
        "best_l1_ratio",
        "cv_best_score",
        "first_5_predictions",
        "inference_time_seconds"
    }
    missing_keys = required_keys - set(res.keys())
    assert not missing_keys, f"JSON report is missing required keys: {missing_keys}"
    assert set(res.keys()) == required_keys, f"JSON report must contain exactly the required keys, got {set(res.keys())}"

    # Preserve the original expected-value assertions.
    assert isinstance(res["best_alpha"], (int, float)), "best_alpha must be a float"
    assert math.isclose(res["best_alpha"], 0.1, abs_tol=1e-5), f"Expected best_alpha to be 0.1, got {res['best_alpha']}"

    assert isinstance(res["best_l1_ratio"], (int, float)), "best_l1_ratio must be a float"
    assert math.isclose(res["best_l1_ratio"], 0.9, abs_tol=1e-5), f"Expected best_l1_ratio to be 0.9, got {res['best_l1_ratio']}"

    assert isinstance(res["cv_best_score"], (int, float)), "cv_best_score must be a float"
    assert math.isclose(res["cv_best_score"], 0.9790, abs_tol=0.0005), f"cv_best_score {res['cv_best_score']} is out of tolerance"

    preds = res["first_5_predictions"]
    assert isinstance(preds, list), "first_5_predictions must be a list"
    assert len(preds) == 5, f"first_5_predictions must have exactly 5 elements, got {len(preds)}"

    expected_preds = [-0.3662, 0.6970, -0.6695, 2.5085, -0.4034]
    for i, (p, e) in enumerate(zip(preds, expected_preds)):
        assert isinstance(p, (int, float)), f"Prediction at index {i} is not a float"
        assert math.isclose(p, e, abs_tol=0.0005), f"Prediction at index {i} was {p}, expected ~{e}"

    inf_time = res["inference_time_seconds"]
    assert isinstance(inf_time, (int, float)), "inference_time_seconds must be a float"
    assert inf_time > 0.0, f"inference_time_seconds must be greater than 0.0, got {inf_time}"
    assert math.isfinite(float(inf_time)), "inference_time_seconds must be finite"

    # Independently derive the tuning result and predictions, then tie the report
    # to both that result and the persisted model.
    search, reference_predictions, batch = reference_results()
    assert math.isclose(float(res["best_alpha"]), float(search.best_params_["alpha"]), abs_tol=1e-12)
    assert math.isclose(float(res["best_l1_ratio"]), float(search.best_params_["l1_ratio"]), abs_tol=1e-12)
    assert math.isclose(float(res["cv_best_score"]), round(float(search.best_score_), 4), abs_tol=1e-12)

    rounded_reference = [round(float(value), 4) for value in reference_predictions[:5]]
    np.testing.assert_allclose(np.asarray(preds, dtype=float), rounded_reference, rtol=0, atol=1e-12)

    loaded_model = load_submitted_model()
    loaded_predictions = loaded_model.predict(batch[FEATURES])
    rounded_loaded = [round(float(value), 4) for value in loaded_predictions[:5]]
    np.testing.assert_allclose(np.asarray(preds, dtype=float), rounded_loaded, rtol=0, atol=1e-12)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
