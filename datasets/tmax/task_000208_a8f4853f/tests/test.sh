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
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import importlib.metadata
import itertools
import json
import os
import subprocess

import joblib
import numpy as np
import pandas as pd
import pytest
import requests
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error

DATASET_PATH = "/home/user/dataset.csv"
FILTERED_PATH = "/home/user/filtered_dataset.csv"
MODEL_PATH = "/home/user/model.pkl"
PACKAGE_PATH = "/app/fast-tracker-1.0"


def expected_filtered_data():
    source = pd.read_csv(DATASET_PATH)
    feature_names = [column for column in source.columns if column != "target"]
    correlations = source[feature_names].corr(method="pearson").abs()

    dropped = set()
    for left, right in itertools.combinations(feature_names, 2):
        if correlations.loc[left, right] > 0.85:
            # The instruction specifies alphabetical, i.e. lexicographic, order.
            dropped.add(max(left, right))

    kept = [column for column in feature_names if column not in dropped]
    return source[kept + ["target"]].copy(), kept, dropped


def reference_model_and_mse():
    filtered, features, dropped = expected_filtered_data()
    model = Ridge(random_state=42)
    model.fit(filtered[features], filtered["target"])
    predictions = model.predict(filtered[features])
    return model, mean_squared_error(filtered["target"], predictions), filtered, features, dropped


def test_fast_tracker_built_and_installed():
    try:
        import fast_tracker
    except ImportError:
        pytest.fail("The 'fast-tracker' package is not installed or cannot be imported.")

    assert importlib.metadata.version("fast-tracker") == "1.0.0"
    assert callable(fast_tracker.log_metric)

    # Exercise the repaired build rather than merely trusting an importable module.
    result = subprocess.run(
        ["make", "-B"], cwd=PACKAGE_PATH, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert result.returncode == 0, f"Vendored package does not build:\n{result.stdout}"
    object_path = os.path.join(PACKAGE_PATH, "src", "math_utils.o")
    assert os.path.isfile(object_path), "make did not produce src/math_utils.o"
    with open(object_path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "math_utils.o is not a compiled ELF object"

    marker = 0.314159265
    fast_tracker.log_metric("verifier_probe", marker)
    assert getattr(fast_tracker, "_metrics", {}).get("verifier_probe") == marker


def test_filtered_dataset_contents():
    assert os.path.isfile(FILTERED_PATH), f"Filtered dataset not found at {FILTERED_PATH}"
    actual = pd.read_csv(FILTERED_PATH)
    expected, features, dropped = expected_filtered_data()

    # For this dataset, lexical alphabetical ordering drops f7 and f6.
    assert dropped == {"f6", "f7"}, f"Unexpected correlation result: {dropped}"
    expected_columns = features + ["target"]
    assert list(actual.columns) == expected_columns, (
        f"Expected columns {expected_columns}, but got {list(actual.columns)}"
    )
    assert len(actual) == 1000, f"Expected 1000 rows, but got {len(actual)}"
    pd.testing.assert_frame_equal(
        actual,
        expected,
        check_dtype=False,
        check_exact=False,
        rtol=1e-12,
        atol=1e-12,
    )


def test_saved_model_is_the_required_fitted_model():
    assert os.path.isfile(MODEL_PATH), f"Model not found at {MODEL_PATH}"
    try:
        actual = joblib.load(MODEL_PATH)
    except Exception as exc:
        pytest.fail(f"Failed to load model from {MODEL_PATH}: {exc}")

    assert isinstance(actual, Ridge), "Saved model is not a Ridge regression model."
    expected, _, filtered, features, _ = reference_model_and_mse()

    required_params = Ridge(random_state=42).get_params(deep=False)
    assert actual.get_params(deep=False) == required_params, (
        "Saved Ridge model does not use the required default parameters and random_state=42"
    )
    assert hasattr(actual, "coef_") and hasattr(actual, "intercept_"), "Saved Ridge is not fitted"
    assert actual.n_features_in_ == len(features)
    np.testing.assert_allclose(actual.coef_, expected.coef_, rtol=1e-10, atol=1e-10)
    np.testing.assert_allclose(actual.intercept_, expected.intercept_, rtol=1e-10, atol=1e-10)
    np.testing.assert_allclose(
        actual.predict(filtered[features]),
        expected.predict(filtered[features]),
        rtol=1e-10,
        atol=1e-10,
    )


def test_service_endpoints_use_required_model_and_metric():
    expected_model, expected_mse, filtered, features, _ = reference_model_and_mse()
    saved_model = joblib.load(MODEL_PATH)

    try:
        response = requests.get("http://127.0.0.1:8080/metrics", timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to GET /metrics: {exc}")
    assert response.status_code == 200, f"GET /metrics returned status {response.status_code}"
    metric_data = response.json()
    assert "mse" in metric_data, "Response JSON missing 'mse' key"
    assert isinstance(metric_data["mse"], (int, float)) and np.isfinite(metric_data["mse"])
    assert np.isclose(metric_data["mse"], expected_mse, rtol=1e-9, atol=1e-12), (
        f"Expected MSE {expected_mse}, got {metric_data['mse']}"
    )

    # Exercise many independently derived inputs, including dataset rows and
    # generated points, rather than permitting a single hard-coded response.
    raw_bytes = open(DATASET_PATH, "rb").read()
    seed = int.from_bytes(hashlib.sha256(raw_bytes).digest()[:8], "little")
    rng = np.random.default_rng(seed)
    matrix = filtered[features].to_numpy()
    row_indices = rng.choice(len(matrix), size=8, replace=False)
    probes = [matrix[index] for index in row_indices]
    probes.extend([
        np.zeros(len(features)),
        matrix.mean(axis=0),
        matrix.std(axis=0),
        rng.normal(matrix.mean(axis=0), matrix.std(axis=0), size=len(features)),
        rng.uniform(matrix.min(axis=0), matrix.max(axis=0), size=len(features)),
    ])

    for probe in probes:
        expected_prediction = float(expected_model.predict(np.asarray(probe).reshape(1, -1))[0])
        saved_prediction = float(saved_model.predict(np.asarray(probe).reshape(1, -1))[0])
        assert np.isclose(saved_prediction, expected_prediction, rtol=1e-10, atol=1e-10)
        try:
            response = requests.post(
                "http://127.0.0.1:8080/predict",
                json={"features": np.asarray(probe, dtype=float).tolist()},
                timeout=5,
            )
        except requests.RequestException as exc:
            pytest.fail(f"Failed to connect to POST /predict: {exc}")
        assert response.status_code == 200, f"POST /predict returned status {response.status_code}"
        prediction_data = response.json()
        assert "prediction" in prediction_data, "Response JSON missing 'prediction' key"
        assert isinstance(prediction_data["prediction"], (int, float))
        assert np.isclose(
            prediction_data["prediction"], expected_prediction, rtol=1e-8, atol=1e-9
        ), f"Expected prediction {expected_prediction}, got {prediction_data['prediction']}"


def test_service_listens_on_exact_ipv4_address():
    listeners = []
    with open("/proc/net/tcp", "r", encoding="utf-8") as handle:
        for line in handle.readlines()[1:]:
            fields = line.split()
            address, port = fields[1].split(":")
            state = fields[3]
            if int(port, 16) == 8080 and state == "0A":
                listeners.append(address)
    assert listeners, "No IPv4 listener found on port 8080"
    assert set(listeners) == {"0100007F"}, (
        f"Service must listen exactly on 127.0.0.1:8080; found addresses {listeners}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
