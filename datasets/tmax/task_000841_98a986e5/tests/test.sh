#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import secrets
import subprocess

import numpy as np
import pytest
import requests

H5_PATH = "/home/user/training_data.h5"
MODEL_PATH = "/home/user/surrogate.pkl"
EXTRACTOR = "/app/legacy_extractor"
URL = "http://127.0.0.1:8000/predict"


def extractor_value(x, y, z):
    result = subprocess.run(
        [EXTRACTOR, repr(float(x)), repr(float(y)), repr(float(z))],
        check=True,
        capture_output=True,
        text=True,
        timeout=5,
    )
    return float(result.stdout.strip())


def true_function(x, y, z):
    return math.sin(x) * (y * y) + math.log(abs(z) + 1.0)


def accurate(pred, expected):
    abs_err = abs(float(pred) - float(expected))
    rel_err = abs_err / max(abs(float(expected)), 1e-9)
    return abs_err < 0.25 or rel_err < 0.05


def post_prediction(x, y, z):
    payload = {"x": float(x), "y": float(y), "z": float(z)}
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the web service at {URL}: {exc}")

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "prediction" in data, f"Response JSON missing 'prediction' key: {data}"
    pred = data["prediction"]
    assert isinstance(pred, (int, float)) and not isinstance(pred, bool), (
        f"Prediction must be a number, got {type(pred)}"
    )
    assert math.isfinite(float(pred)), f"Prediction is not finite: {pred}"
    return float(pred)


def load_model():
    import joblib
    from sklearn.base import BaseEstimator, is_regressor
    from sklearn.utils.validation import check_is_fitted

    model = joblib.load(MODEL_PATH)
    assert isinstance(model, BaseEstimator), "Saved artifact is not a scikit-learn estimator."
    assert type(model).__module__.startswith("sklearn."), (
        "The top-level saved model must be implemented by scikit-learn."
    )
    assert is_regressor(model), "Saved estimator is not a regressor."
    check_is_fitted(model)

    # Reject custom estimator wrappers hidden inside a scikit-learn Pipeline or search.
    for _, value in model.get_params(deep=True).items():
        if isinstance(value, BaseEstimator):
            assert type(value).__module__.startswith("sklearn."), (
                "Saved model contains a non-scikit-learn estimator wrapper."
            )
            if type(value).__name__ == "FunctionTransformer":
                assert getattr(value, "func", None) is None, (
                    "Custom formula FunctionTransformer is not a trained surrogate."
                )

    probe = np.asarray([[0.37, 1.29, 4.11], [4.63, 3.22, 0.18]], dtype=float)
    predictions = np.asarray(model.predict(probe), dtype=float).reshape(-1)
    assert predictions.shape == (2,), "Saved model does not return one prediction per sample."
    assert np.isfinite(predictions).all(), "Saved model returned non-finite predictions."
    return model


def test_files_exist():
    assert os.path.exists(H5_PATH), f"Training data file {H5_PATH} does not exist."
    assert os.path.isfile(H5_PATH), f"{H5_PATH} is not a file."
    assert os.path.getsize(H5_PATH) > 0, f"{H5_PATH} is empty."

    assert os.path.exists(MODEL_PATH), f"Model file {MODEL_PATH} does not exist."
    assert os.path.isfile(MODEL_PATH), f"{MODEL_PATH} is not a file."
    assert os.path.getsize(MODEL_PATH) > 0, f"{MODEL_PATH} is empty."


def test_hdf5_contents_and_labels():
    try:
        import h5py
    except ImportError:
        pytest.fail("h5py is not installed, cannot verify HDF5 contents.")

    try:
        with h5py.File(H5_PATH, "r") as handle:
            assert "X" in handle, "Dataset 'X' not found in HDF5 file."
            assert "y" in handle, "Dataset 'y' not found in HDF5 file."
            assert handle["X"].shape == (2000, 3), (
                f"Expected X shape (2000, 3), got {handle['X'].shape}"
            )
            assert handle["y"].shape in ((2000,), (2000, 1)), (
                f"Expected y shape (2000,), got {handle['y'].shape}"
            )
            X = np.asarray(handle["X"][:], dtype=float)
            labels = np.asarray(handle["y"][:], dtype=float).reshape(-1)
    except Exception as exc:
        pytest.fail(f"Failed to read HDF5 file: {exc}")

    assert np.isfinite(X).all() and np.isfinite(labels).all(), "Dataset contains non-finite values."
    assert np.all((X >= 0.0) & (X <= 5.0)), "X values must be between 0.0 and 5.0."
    assert np.unique(X, axis=0).shape[0] >= 1990, "X does not contain 2,000 random samples."

    # A very loose uniformity check that catches constant, grid-only, and concentrated fabrications.
    for column in range(3):
        counts, _ = np.histogram(X[:, column], bins=5, range=(0.0, 5.0))
        assert np.all(counts >= 250), (
            f"Column {column} is not plausibly uniform on [0, 5]: bin counts {counts.tolist()}"
        )

    # Derive every expected label by executing the supplied binary.
    expected = np.asarray([extractor_value(*row) for row in X], dtype=float)
    assert np.allclose(labels, expected, rtol=0.0, atol=2e-5), (
        f"HDF5 labels do not match {EXTRACTOR}; maximum error is "
        f"{float(np.max(np.abs(labels - expected)))}"
    )


def test_saved_model_is_valid_and_accurate():
    model = load_model()
    rng = random.Random(secrets.randbits(128))
    points = np.asarray(
        [[rng.uniform(0.0, 5.0) for _ in range(3)] for _ in range(32)],
        dtype=float,
    )
    predictions = np.asarray(model.predict(points), dtype=float).reshape(-1)
    assert predictions.shape == (32,)
    assert np.isfinite(predictions).all()

    for point, pred in zip(points, predictions):
        expected = extractor_value(*point)
        assert accurate(pred, expected), (
            f"Saved model prediction {pred} for {point.tolist()} is too far from "
            f"binary output {expected}."
        )


def test_web_service_predictions():
    # Preserve the original deterministic behavioral assertions.
    rng = random.Random(42)
    for _ in range(10):
        x = rng.uniform(0.0, 5.0)
        y = rng.uniform(0.0, 5.0)
        z = rng.uniform(0.0, 5.0)
        pred = post_prediction(x, y, z)
        expected = true_function(x, y, z)
        assert accurate(pred, expected), (
            f"Prediction {pred} for input {{'x': {x}, 'y': {y}, 'z': {z}}} "
            f"is too far from expected {expected}."
        )

    # Use unpredictable held-out points, derive answers from the binary, and require
    # the HTTP service to return the saved model's actual predictions.
    model = load_model()
    rng = random.Random(secrets.randbits(128))
    points = np.asarray(
        [[rng.uniform(0.0, 5.0) for _ in range(3)] for _ in range(24)],
        dtype=float,
    )
    model_predictions = np.asarray(model.predict(points), dtype=float).reshape(-1)

    for point, model_pred in zip(points, model_predictions):
        service_pred = post_prediction(*point)
        assert math.isclose(service_pred, float(model_pred), rel_tol=1e-8, abs_tol=1e-8), (
            f"Service prediction {service_pred} does not match saved model prediction "
            f"{float(model_pred)} for {point.tolist()}."
        )
        expected = extractor_value(*point)
        assert accurate(service_pred, expected), (
            f"Prediction {service_pred} for {point.tolist()} is too far from "
            f"binary output {expected}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
