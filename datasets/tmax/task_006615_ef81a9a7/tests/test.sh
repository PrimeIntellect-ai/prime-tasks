#!/bin/bash
set -u
mkdir -p /logs/verifier /tmp/auditmods /tmp/model_audit
rm -f /tmp/model_audit/*

cat <<'PY_EOF' > /tmp/auditmods/sitecustomize.py
import json
import os
import types
import numpy as np
import sklearn.preprocessing as preprocessing
import sklearn.linear_model as linear_model

AUDIT_DIR = os.environ.get("MODEL_AUDIT_DIR")
os.makedirs(AUDIT_DIR, exist_ok=True)
_counter = 0

def record(event, **fields):
    global _counter
    fields["event"] = event
    fields["index"] = _counter
    _counter += 1
    with open(os.path.join(AUDIT_DIR, "events.jsonl"), "a") as f:
        f.write(json.dumps(fields) + "\n")

def save_array(label, value):
    global _counter
    name = f"{_counter:04d}_{label}.npy"
    np.save(os.path.join(AUDIT_DIR, name), np.asarray(value), allow_pickle=False)
    return name

_original_seed = np.random.seed
_original_uniform = np.random.uniform
_original_normal = np.random.normal
_original_pf = preprocessing.PolynomialFeatures
_original_lr = linear_model.LinearRegression
_original_ridge = linear_model.Ridge

def audited_seed(seed=None):
    record("seed", seed=seed)
    return _original_seed(seed)

def audited_uniform(low=0.0, high=1.0, size=None):
    result = _original_uniform(low, high, size)
    filename = save_array("uniform", result)
    record("uniform", low=low, high=high, size=size, array=filename)
    return result

def audited_normal(loc=0.0, scale=1.0, size=None):
    result = _original_normal(loc, scale, size)
    filename = save_array("normal", result)
    record("normal", loc=loc, scale=scale, size=size, array=filename)
    return result

def PolynomialFeatures(*args, **kwargs):
    obj = _original_pf(*args, **kwargs)
    record("poly_init", degree=obj.degree, include_bias=obj.include_bias)
    original_fit_transform = obj.fit_transform
    original_transform = obj.transform

    def fit_transform(self, X, *a, **k):
        in_file = save_array("poly_fit_input", X)
        result = original_fit_transform(X, *a, **k)
        out_file = save_array("poly_fit_output", result)
        record("poly_fit_transform", input=in_file, output=out_file)
        return result

    def transform(self, X, *a, **k):
        in_file = save_array("poly_transform_input", X)
        result = original_transform(X, *a, **k)
        out_file = save_array("poly_transform_output", result)
        record("poly_transform", input=in_file, output=out_file)
        return result

    obj.fit_transform = types.MethodType(fit_transform, obj)
    obj.transform = types.MethodType(transform, obj)
    return obj

def wrap_model(obj, kind):
    record(kind + "_init", params=obj.get_params(deep=False))
    original_fit = obj.fit
    original_predict = obj.predict

    def fit(self, X, y, *a, **k):
        x_file = save_array(kind + "_fit_X", X)
        y_file = save_array(kind + "_fit_y", y)
        record(kind + "_fit", X=x_file, y=y_file)
        original_fit(X, y, *a, **k)
        return self

    def predict(self, X, *a, **k):
        x_file = save_array(kind + "_predict_X", X)
        result = original_predict(X, *a, **k)
        out_file = save_array(kind + "_prediction", result)
        record(kind + "_predict", X=x_file, output=out_file)
        return result

    obj.fit = types.MethodType(fit, obj)
    obj.predict = types.MethodType(predict, obj)
    return obj

def LinearRegression(*args, **kwargs):
    return wrap_model(_original_lr(*args, **kwargs), "linear")

def Ridge(*args, **kwargs):
    return wrap_model(_original_ridge(*args, **kwargs), "ridge")

np.random.seed = audited_seed
np.random.uniform = audited_uniform
np.random.normal = audited_normal
preprocessing.PolynomialFeatures = PolynomialFeatures
linear_model.LinearRegression = LinearRegression
linear_model.Ridge = Ridge
PY_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import sys

import numpy as np
import pytest
from sklearn.preprocessing import PolynomialFeatures
from sklearn.linear_model import LinearRegression, Ridge

SCRIPT = "/home/user/fit_models.py"
PREDICTIONS = "/home/user/predictions.txt"
AUDIT_DIR = "/tmp/model_audit"

@pytest.fixture(scope="session", autouse=True)
def execute_submitted_script():
    assert os.path.isfile(SCRIPT), f"Required script {SCRIPT} is missing."
    assert os.path.isfile(SCRIPT) and SCRIPT.endswith(".py"), f"{SCRIPT} is not a Python script."

    if os.path.exists(PREDICTIONS):
        os.remove(PREDICTIONS)
    for name in os.listdir(AUDIT_DIR):
        os.remove(os.path.join(AUDIT_DIR, name))

    env = os.environ.copy()
    env["MODEL_AUDIT_DIR"] = AUDIT_DIR
    env["PYTHONPATH"] = "/tmp/auditmods" + (
        os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
    )
    completed = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert completed.returncode == 0, (
        f"Executing {SCRIPT} failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(PREDICTIONS), (
        "Executing fit_models.py did not create /home/user/predictions.txt"
    )


def load_events():
    path = os.path.join(AUDIT_DIR, "events.jsonl")
    assert os.path.isfile(path), "The submitted script did not execute the required numerical pipeline."
    with open(path) as f:
        return [json.loads(line) for line in f if line.strip()]


def one_event(events, name):
    matches = [event for event in events if event["event"] == name]
    assert matches, f"Required operation {name!r} was not executed."
    return matches[-1]


def array_from(event, field):
    return np.load(os.path.join(AUDIT_DIR, event[field]), allow_pickle=False)


def test_script_executes_required_modeling_pipeline():
    events = load_events()

    seed = one_event(events, "seed")
    assert seed["seed"] == 42

    uniform = one_event(events, "uniform")
    normal = one_event(events, "normal")
    assert uniform["low"] == pytest.approx(0.99)
    assert uniform["high"] == pytest.approx(1.01)
    assert uniform["size"] == 1000
    assert normal["loc"] == pytest.approx(0.0)
    assert normal["scale"] == pytest.approx(0.001)
    assert normal["size"] == 1000

    rng = np.random.RandomState(42)
    expected_x_flat = rng.uniform(0.99, 1.01, 1000)
    expected_epsilon_flat = rng.normal(0.0, 0.001, 1000)
    np.testing.assert_array_equal(array_from(uniform, "array"), expected_x_flat)
    np.testing.assert_array_equal(array_from(normal, "array"), expected_epsilon_flat)

    poly_init = one_event(events, "poly_init")
    assert poly_init["degree"] == 10
    assert poly_init["include_bias"] is False

    poly_fit = one_event(events, "poly_fit_transform")
    x = array_from(poly_fit, "input")
    features = array_from(poly_fit, "output")
    expected_x = expected_x_flat.reshape(1000, 1)
    expected_epsilon = expected_epsilon_flat.reshape(1000, 1)
    expected_y = 3 * expected_x**2 + 2 * expected_x + 1 + expected_epsilon
    assert x.shape == (1000, 1)
    np.testing.assert_array_equal(x, expected_x)

    independent_poly = PolynomialFeatures(degree=10, include_bias=False)
    expected_features = independent_poly.fit_transform(expected_x)
    np.testing.assert_allclose(features, expected_features, rtol=0, atol=0)

    linear_init = one_event(events, "linear_init")
    ridge_init = one_event(events, "ridge_init")
    assert ridge_init["params"]["alpha"] == pytest.approx(1.0)
    assert linear_init["params"].get("fit_intercept", True) is True

    linear_fit = one_event(events, "linear_fit")
    ridge_fit = one_event(events, "ridge_fit")
    for fit_event in (linear_fit, ridge_fit):
        np.testing.assert_allclose(array_from(fit_event, "X"), expected_features, rtol=0, atol=0)
        np.testing.assert_allclose(array_from(fit_event, "y"), expected_y, rtol=0, atol=1e-15)

    poly_transform = one_event(events, "poly_transform")
    test_input = array_from(poly_transform, "input")
    test_features = array_from(poly_transform, "output")
    np.testing.assert_array_equal(test_input, np.array([[1.0]]))
    expected_test_features = independent_poly.transform([[1.0]])
    np.testing.assert_allclose(test_features, expected_test_features, rtol=0, atol=0)

    linear_predict = one_event(events, "linear_predict")
    ridge_predict = one_event(events, "ridge_predict")
    np.testing.assert_allclose(array_from(linear_predict, "X"), expected_test_features, rtol=0, atol=0)
    np.testing.assert_allclose(array_from(ridge_predict, "X"), expected_test_features, rtol=0, atol=0)

    with open(PREDICTIONS) as f:
        parts = f.read().strip().split(",")
    assert len(parts) == 2
    written = np.array([float(parts[0].strip()), float(parts[1].strip())])
    executed = np.array([
        array_from(linear_predict, "output").reshape(-1)[0],
        array_from(ridge_predict, "output").reshape(-1)[0],
    ])
    np.testing.assert_allclose(written, executed, rtol=0, atol=1e-2)

    expected_linear = LinearRegression().fit(expected_features, expected_y).predict(expected_test_features)[0]
    expected_ridge = Ridge(alpha=1.0).fit(expected_features, expected_y).predict(expected_test_features)[0]
    np.testing.assert_allclose(written, [expected_linear, expected_ridge], rtol=0, atol=1e-2)


def test_predictions_file_exists():
    """Test that the predictions.txt file was created."""
    file_path = "/home/user/predictions.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing. Did you run your script?"


def test_predictions_values():
    """Test that the predictions in the file are correct within a tolerance."""
    file_path = "/home/user/predictions.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content, "The predictions.txt file is empty."

    parts = content.split(",")
    assert len(parts) == 2, f"Expected 2 comma-separated values in predictions.txt, got {len(parts)}."

    try:
        pred_lr = float(parts[0].strip())
        pred_ridge = float(parts[1].strip())
    except ValueError:
        assert False, "Could not parse the values in predictions.txt as floats."

    expected_lr = 5.9995166270422215
    expected_ridge = 5.999971936444853
    tolerance = 1e-2

    assert abs(pred_lr - expected_lr) <= tolerance, (
        f"LinearRegression prediction {pred_lr} is not within {tolerance} "
        f"of expected value {expected_lr}."
    )

    assert abs(pred_ridge - expected_ridge) <= tolerance, (
        f"Ridge prediction {pred_ridge} is not within {tolerance} "
        f"of expected value {expected_ridge}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
