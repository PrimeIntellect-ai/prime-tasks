#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess
import sys
import tempfile

import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

RESULTS_PATH = "/home/user/results.json"
EVALUATE_SCRIPT_PATH = "/home/user/evaluate.py"
DATA_PATH = "/home/user/data.csv"


def load_results():
    with open(RESULTS_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} is not valid JSON.")


def assert_schema_and_plausibility(data):
    expected_keys = {"fixed_mse", "mse_std_err", "corr_A_B", "avg_inference_us"}
    actual_keys = set(data.keys())
    missing = expected_keys - actual_keys
    extra = actual_keys - expected_keys

    assert not missing, f"results.json is missing keys: {missing}"
    assert not extra, f"results.json has unexpected keys: {extra}"

    for key in expected_keys:
        val = data[key]
        assert isinstance(val, (int, float)), \
            f"Value for '{key}' must be a float, got {type(val).__name__}"

    assert data["fixed_mse"] > 0, "MSE should be strictly positive."
    assert data["mse_std_err"] > 0, "MSE standard error should be strictly positive."
    assert -1.0 <= data["corr_A_B"] <= 1.0, \
        "Pearson correlation must be between -1 and 1."
    assert data["avg_inference_us"] > 0, \
        "Average inference time must be strictly positive."


def expected_metrics(df):
    X = df[["A", "B", "C"]]
    y = df["target"]
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)

    model = Ridge()
    model.fit(X_train_scaled, y_train)
    predictions = model.predict(X_test_scaled)
    mse = mean_squared_error(y_test, predictions)
    corr = np.corrcoef(X_test_scaled[:, 0], X_test_scaled[:, 1])[0, 1]

    np.random.seed(42)
    bootstrap_mses = []
    for _ in range(1000):
        indices = np.random.choice(len(y_test), size=len(y_test), replace=True)
        bootstrap_mses.append(
            mean_squared_error(y_test.iloc[indices], predictions[indices])
        )

    return {
        "fixed_mse": float(mse),
        "mse_std_err": float(np.std(bootstrap_mses)),
        "corr_A_B": float(corr),
    }


RUNNER = r'''
import json
import os
import runpy
import time
import numpy as np
import sklearn.linear_model as linear_model

RealRidge = linear_model.Ridge

class CountingRidge(RealRidge):
    single_calls = 0
    total_calls = 0
    single_predict_ns = 0

    def predict(self, X):
        arr = np.asarray(X)
        start = time.perf_counter_ns()
        result = super().predict(X)
        elapsed = time.perf_counter_ns() - start
        type(self).total_calls += 1
        if arr.ndim >= 2 and arr.shape[0] == 1:
            type(self).single_calls += 1
            type(self).single_predict_ns += elapsed
        return result

linear_model.Ridge = CountingRidge
os.chdir("/home/user")
runpy.run_path("/home/user/evaluate.py", run_name="__main__")
with open(os.environ["PREDICT_STATS_PATH"], "w") as f:
    json.dump({
        "single_calls": CountingRidge.single_calls,
        "total_calls": CountingRidge.total_calls,
        "single_predict_ns": CountingRidge.single_predict_ns,
    }, f)
'''


def run_submission():
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)

    fd, stats_path = tempfile.mkstemp(prefix="predict_stats_", suffix=".json")
    os.close(fd)
    os.remove(stats_path)
    env = os.environ.copy()
    env["PREDICT_STATS_PATH"] = stats_path
    try:
        completed = subprocess.run(
            [sys.executable, "-c", RUNNER],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=90,
        )
        assert completed.returncode == 0, (
            "evaluate.py failed when executed:\n"
            + completed.stdout + "\n" + completed.stderr
        )
        assert os.path.isfile(RESULTS_PATH), \
            "evaluate.py did not generate /home/user/results.json"
        assert os.path.isfile(stats_path), "Prediction instrumentation was not completed"
        with open(stats_path, "r") as f:
            stats = json.load(f)
        return load_results(), stats
    finally:
        if os.path.exists(stats_path):
            os.remove(stats_path)


def make_dataset(seed, n, variant):
    rng = np.random.default_rng(seed)
    A = rng.normal(loc=variant * 0.7, scale=1.0 + variant * 0.35, size=n)
    B = 0.45 * A + rng.normal(scale=0.35 + 0.1 * variant, size=n)
    C = rng.normal(size=n) * (2.0 + variant) + 0.25 * A * A
    target = (
        1.4 * A - 0.75 * B + 1.9 * C
        + 0.12 * A * B + rng.normal(scale=0.18 + 0.03 * variant, size=n)
    )
    return pd.DataFrame({"A": A, "B": B, "C": C, "target": target})


def test_evaluate_script_exists():
    assert os.path.exists(EVALUATE_SCRIPT_PATH), f"Missing script: {EVALUATE_SCRIPT_PATH}"
    assert os.path.isfile(EVALUATE_SCRIPT_PATH), f"Path is not a file: {EVALUATE_SCRIPT_PATH}"


def test_results_json_exists():
    assert os.path.exists(RESULTS_PATH), f"Missing results file: {RESULTS_PATH}"
    assert os.path.isfile(RESULTS_PATH), f"Path is not a file: {RESULTS_PATH}"


def test_results_json_schema_and_types():
    assert_schema_and_plausibility(load_results())


def test_results_plausible_values():
    data = load_results()
    assert data["fixed_mse"] > 0, "MSE should be strictly positive."
    assert data["mse_std_err"] > 0, "MSE standard error should be strictly positive."
    assert -1.0 <= data["corr_A_B"] <= 1.0, \
        "Pearson correlation must be between -1 and 1."
    assert data["avg_inference_us"] > 0, \
        "Average inference time must be strictly positive."


def test_script_executes_correct_pipeline_on_unseen_data():
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()
    original_results = None
    if os.path.exists(RESULTS_PATH):
        with open(RESULTS_PATH, "rb") as f:
            original_results = f.read()

    try:
        cases = [(73, 1), (127, 2)]
        for n, variant in cases:
            seed = secrets.randbits(63)
            generated = make_dataset(seed, n, variant)
            generated.to_csv(DATA_PATH, index=False)
            reloaded = pd.read_csv(DATA_PATH)
            expected = expected_metrics(reloaded)

            actual, stats = run_submission()
            assert_schema_and_plausibility(actual)

            for key in ("fixed_mse", "mse_std_err", "corr_A_B"):
                assert math.isfinite(float(actual[key])), f"{key} must be finite"
                assert np.isclose(
                    float(actual[key]), expected[key], rtol=1e-10, atol=1e-12
                ), f"Incorrect {key}: expected {expected[key]!r}, got {actual[key]!r}"

            assert math.isfinite(float(actual["avg_inference_us"])), \
                "Average inference time must be finite"
            assert stats["single_calls"] >= 1000, (
                "evaluate.py must call model.predict() separately for each of "
                "the 1000 single-sample benchmark iterations"
            )
            assert stats["total_calls"] >= 1001, \
                "Expected both test-set prediction and 1000 benchmark predictions"
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        if original_results is None:
            if os.path.exists(RESULTS_PATH):
                os.remove(RESULTS_PATH)
        else:
            with open(RESULTS_PATH, "wb") as f:
                f.write(original_results)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
