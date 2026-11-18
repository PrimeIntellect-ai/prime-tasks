#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import runpy
import numpy as np
import pytest

import sklearn.model_selection as model_selection
import sklearn.preprocessing as preprocessing
import sklearn.linear_model as linear_model
import sklearn.metrics as metrics_module

STATE = {}

@pytest.fixture(scope="session", autouse=True)
def execute_and_trace_submission():
    script_path = "/home/user/evaluate.py"
    metrics_path = "/home/user/metrics.json"
    assert os.path.isfile(script_path), f"The script {script_path} is missing."

    if os.path.exists(metrics_path):
        os.remove(metrics_path)

    original_split = model_selection.train_test_split
    original_scaler = preprocessing.StandardScaler
    original_logistic = linear_model.LogisticRegression
    original_accuracy = metrics_module.accuracy_score
    original_seed = np.random.seed

    trace = {
        "order": 0,
        "seeds": [],
        "splits": [],
        "fits": [],
        "transforms": [],
        "models": [],
        "accuracy_calls": [],
    }

    def next_order():
        trace["order"] += 1
        return trace["order"]

    def tracked_seed(value, *args, **kwargs):
        trace["seeds"].append(value)
        return original_seed(value, *args, **kwargs)

    def tracked_split(X, y, *args, **kwargs):
        order = next_order()
        result = original_split(X, y, *args, **kwargs)
        trace["splits"].append({
            "order": order,
            "X": np.asarray(X).copy(),
            "y": np.asarray(y).copy(),
            "args": args,
            "kwargs": dict(kwargs),
            "result": tuple(np.asarray(v).copy() for v in result),
        })
        return result

    class TrackedScaler(original_scaler):
        def fit(self, X, y=None, **fit_params):
            trace["fits"].append({"order": next_order(), "input": np.asarray(X).copy()})
            return super().fit(X, y, **fit_params)

        def transform(self, X, copy=None):
            output = super().transform(X, copy=copy)
            trace["transforms"].append({
                "order": next_order(),
                "input": np.asarray(X).copy(),
                "output": np.asarray(output).copy(),
            })
            return output

    def tracked_logistic(*args, **kwargs):
        model = original_logistic(*args, **kwargs)
        record = {"args": args, "kwargs": dict(kwargs), "fits": [], "predictions": []}
        trace["models"].append(record)
        original_fit = model.fit
        original_predict = model.predict

        def fit(X, y, *fit_args, **fit_kwargs):
            record["fits"].append({"X": np.asarray(X).copy(), "y": np.asarray(y).copy()})
            return original_fit(X, y, *fit_args, **fit_kwargs)

        def predict(X, *predict_args, **predict_kwargs):
            result = original_predict(X, *predict_args, **predict_kwargs)
            record["predictions"].append({
                "X": np.asarray(X).copy(),
                "result": np.asarray(result).copy(),
            })
            return result

        model.fit = fit
        model.predict = predict
        return model

    def tracked_accuracy(y_true, y_pred, *args, **kwargs):
        result = original_accuracy(y_true, y_pred, *args, **kwargs)
        trace["accuracy_calls"].append({
            "y_true": np.asarray(y_true).copy(),
            "y_pred": np.asarray(y_pred).copy(),
            "result": result,
        })
        return result

    np.random.seed = tracked_seed
    model_selection.train_test_split = tracked_split
    preprocessing.StandardScaler = TrackedScaler
    linear_model.LogisticRegression = tracked_logistic
    metrics_module.accuracy_score = tracked_accuracy
    try:
        runpy.run_path(script_path, run_name="__main__")
    finally:
        np.random.seed = original_seed
        model_selection.train_test_split = original_split
        preprocessing.StandardScaler = original_scaler
        linear_model.LogisticRegression = original_logistic
        metrics_module.accuracy_score = original_accuracy

    STATE["trace"] = trace
    STATE["originals"] = (original_split, original_scaler, original_logistic, original_accuracy)


def expected_pipeline():
    original_split, original_scaler, original_logistic, original_accuracy = STATE["originals"]
    np.random.seed(42)
    X = np.random.randn(1000, 20)
    X[:500, 0] += 1.5
    y = np.array([1] * 500 + [0] * 500)
    X_train, X_test, y_train, y_test = original_split(
        X, y, test_size=0.2, random_state=42
    )
    scaler = original_scaler()
    scaler.fit(X_train)
    X_train_scaled = scaler.transform(X_train)
    X_test_scaled = scaler.transform(X_test)
    model = original_logistic(random_state=42)
    model.fit(X_train_scaled, y_train)
    y_pred = model.predict(X_test_scaled)
    return X, y, X_train, X_test, y_train, y_test, original_accuracy(y_test, y_pred)


def test_metrics_json_exists_and_correct():
    """Check that metrics.json exists and contains the correct accuracy and inference_time."""
    metrics_path = "/home/user/metrics.json"
    assert os.path.isfile(metrics_path), f"The file {metrics_path} does not exist. Did you run the script?"

    with open(metrics_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{metrics_path} is not valid JSON.")

    assert "accuracy" in data, "metrics.json is missing the 'accuracy' key."
    assert "inference_time" in data, "metrics.json is missing the 'inference_time' key."

    # The correct accuracy after fixing the leakage is 0.785
    expected_accuracy = 0.785
    actual_accuracy = data["accuracy"]
    assert abs(actual_accuracy - expected_accuracy) < 1e-5, \
        f"Expected accuracy to be approximately {expected_accuracy}, but got {actual_accuracy}. Data leakage might not be fixed correctly."

    independently_computed = expected_pipeline()[-1]
    assert abs(actual_accuracy - independently_computed) < 1e-12, \
        "The reported accuracy does not match an independently computed train-only scaling pipeline."

    actual_time = data["inference_time"]
    assert isinstance(actual_time, (int, float)) and actual_time >= 0, \
        f"Expected inference_time to be a non-negative number, got {actual_time}."


def test_executed_pipeline_splits_before_fitting_scaler():
    trace = STATE["trace"]
    X, y, X_train, X_test, y_train, y_test, expected_accuracy = expected_pipeline()

    assert 42 in trace["seeds"], "The data-generation seed 42 was not maintained."

    matching_splits = [
        s for s in trace["splits"]
        if np.array_equal(s["X"], X) and np.array_equal(s["y"], y)
    ]
    assert matching_splits, "The generated raw dataset was not split before scaling."
    split = matching_splits[0]
    assert split["kwargs"].get("random_state") == 42, "The split random_state must remain 42."
    assert split["kwargs"].get("test_size") == 0.2, "The original test_size must be maintained."

    assert trace["fits"], "StandardScaler.fit (or fit_transform) was not executed."
    assert all(f["order"] > split["order"] for f in trace["fits"]), \
        "The scaler was fitted before train_test_split."
    assert all(np.array_equal(f["input"], X_train) for f in trace["fits"]), \
        "The scaler must be fitted only on X_train."

    train_transforms = [t for t in trace["transforms"] if np.array_equal(t["input"], X_train)]
    test_transforms = [t for t in trace["transforms"] if np.array_equal(t["input"], X_test)]
    assert train_transforms, "The fitted scaler was not used to transform X_train."
    assert test_transforms, "The fitted scaler was not used to transform X_test."

    seeded_models = [m for m in trace["models"] if m["kwargs"].get("random_state") == 42]
    assert seeded_models, "LogisticRegression random_state must remain 42."

    valid_model = None
    for model in seeded_models:
        trained_on_scaled_train = any(
            np.array_equal(fit["X"], transformed["output"])
            and np.array_equal(fit["y"], y_train)
            for fit in model["fits"] for transformed in train_transforms
        )
        predicted_on_scaled_test = any(
            np.array_equal(pred["X"], transformed["output"])
            for pred in model["predictions"] for transformed in test_transforms
        )
        if trained_on_scaled_train and predicted_on_scaled_test:
            valid_model = model
            break

    assert valid_model is not None, \
        "The model must be trained on scaled training data and predict on scaled test data."

    valid_predictions = [
        pred["result"] for pred in valid_model["predictions"]
        if any(np.array_equal(pred["X"], t["output"]) for t in test_transforms)
    ]
    assert any(abs(float(STATE["originals"][3](y_test, pred)) - expected_accuracy) < 1e-12
               for pred in valid_predictions), \
        "The benchmarked model predictions do not produce the expected corrected accuracy."

    assert any(
        np.array_equal(call["y_true"], y_test)
        and any(np.array_equal(call["y_pred"], pred) for pred in valid_predictions)
        for call in trace["accuracy_calls"]
    ), "accuracy_score was not computed from the model's test-set predictions."


def test_evaluate_script_fixed():
    """Check that evaluate.py has been updated to fix the data leakage."""
    script_path = "/home/user/evaluate.py"
    assert os.path.isfile(script_path), f"The script {script_path} is missing."

    with open(script_path, 'r') as f:
        content = f.read()

    # It should no longer fit_transform the entire X
    assert "scaler.fit_transform(X)" not in content, \
        "The script still contains `scaler.fit_transform(X)`. The data leakage is not fully fixed."

    # It should perform train_test_split on X, not X_scaled
    assert "train_test_split(X_scaled" not in content, \
        "The script still splits `X_scaled`. You must split `X` before scaling."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
