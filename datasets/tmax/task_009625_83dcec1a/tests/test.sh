#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

PIPELINE = Path("/home/user/pipeline.py")
DATASET = Path("/home/user/dataset.csv")
RESULTS = Path("/home/user/results.json")
HOOK_DIR = Path("/tmp/pipeline_verifier_hooks")
EVENTS = Path("/tmp/pipeline_verifier_events.jsonl")

HOOK_SOURCE = r'''
import json
import os
import numpy as np

_EVENT_FILE = os.environ["PIPELINE_VERIFY_EVENTS"]
_EXPECTED_X = np.load(os.environ["PIPELINE_EXPECTED_X"], allow_pickle=False)
_EXPECTED_Y = np.load(os.environ["PIPELINE_EXPECTED_Y"], allow_pickle=False)
_EXPECTED_FULL = np.load(os.environ["PIPELINE_EXPECTED_FULL"], allow_pickle=False)
_EXPECTED_SCALED_INPUT = np.load(os.environ["PIPELINE_EXPECTED_SCALER_INPUT"], allow_pickle=False)

def _event(name):
    with open(_EVENT_FILE, "a", encoding="utf-8") as f:
        f.write(json.dumps({"event": name}) + "\n")

def _same(actual, expected):
    try:
        arr = np.asarray(actual, dtype=float)
    except Exception:
        return False
    return arr.shape == expected.shape and np.allclose(arr, expected, rtol=0, atol=1e-10, equal_nan=True)

import sklearn.model_selection as _ms
_original_split = _ms.train_test_split

def checked_train_test_split(*arrays, **kwargs):
    if kwargs.get("random_state") != 42:
        raise RuntimeError("train_test_split must use random_state=42")
    if kwargs.get("shuffle", True) is False:
        raise RuntimeError("train_test_split must use its normal shuffled split")
    test_size = kwargs.get("test_size")
    train_size = kwargs.get("train_size")
    if test_size != 0.2 and train_size != 0.8:
        raise RuntimeError("train_test_split must make an 80/20 split")
    if len(arrays) == 1:
        if not _same(arrays[0], _EXPECTED_FULL):
            raise RuntimeError("Data was changed or shuffled before train_test_split")
    elif len(arrays) == 2:
        if not _same(arrays[0], _EXPECTED_X) or not _same(arrays[1], _EXPECTED_Y):
            raise RuntimeError("Features/target were changed or shuffled before train_test_split")
    else:
        raise RuntimeError("Unexpected train_test_split inputs")
    _event("train_test_split")
    return _original_split(*arrays, **kwargs)

_ms.train_test_split = checked_train_test_split

import sklearn.preprocessing as _pre
_OriginalScaler = _pre.StandardScaler

class CheckedStandardScaler(_OriginalScaler):
    def fit(self, X, y=None, sample_weight=None):
        if not _same(X, _EXPECTED_SCALED_INPUT):
            raise RuntimeError("StandardScaler was not fitted only on the selected training data")
        _event("scaler_fit")
        return super().fit(X, y=y, sample_weight=sample_weight)

_pre.StandardScaler = CheckedStandardScaler

import sklearn.linear_model as _lm
_OriginalLinearRegression = _lm.LinearRegression

class CheckedLinearRegression(_OriginalLinearRegression):
    def fit(self, X, y, sample_weight=None):
        _event("linear_fit")
        return super().fit(X, y, sample_weight=sample_weight)

    def predict(self, X):
        _event("linear_predict")
        return super().predict(X)

_lm.LinearRegression = CheckedLinearRegression
'''


def derive_expected(df):
    X = df.drop(columns=["target"])
    y = df["target"]
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    correlations = X_train.corrwith(y_train)
    selected = [name for name in X.columns if abs(correlations[name]) >= 0.25]
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train[selected])
    X_test_scaled = scaler.transform(X_test[selected])
    model = LinearRegression()
    model.fit(X_train_scaled, y_train)
    mse = round(float(mean_squared_error(y_test, model.predict(X_test_scaled))), 4)
    return selected, mse, X_train[selected].to_numpy(dtype=float)


def read_results():
    assert RESULTS.exists(), f"The results file is missing at {RESULTS}"
    assert RESULTS.is_file(), f"The path {RESULTS} is not a file"
    with RESULTS.open("r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {RESULTS} does not contain valid JSON.")


def run_and_check(df):
    expected_features, expected_mse, expected_scaler_input = derive_expected(df)
    X = df.drop(columns=["target"])
    y = df["target"]

    HOOK_DIR.mkdir(parents=True, exist_ok=True)
    (HOOK_DIR / "sitecustomize.py").write_text(HOOK_SOURCE, encoding="utf-8")
    np.save("/tmp/expected_x.npy", X.to_numpy(dtype=float))
    np.save("/tmp/expected_y.npy", y.to_numpy(dtype=float))
    np.save("/tmp/expected_full.npy", df.to_numpy(dtype=float))
    np.save("/tmp/expected_scaler_input.npy", expected_scaler_input)
    EVENTS.unlink(missing_ok=True)
    RESULTS.unlink(missing_ok=True)

    env = os.environ.copy()
    env.update({
        "PYTHONPATH": str(HOOK_DIR),
        "PIPELINE_VERIFY_EVENTS": str(EVENTS),
        "PIPELINE_EXPECTED_X": "/tmp/expected_x.npy",
        "PIPELINE_EXPECTED_Y": "/tmp/expected_y.npy",
        "PIPELINE_EXPECTED_FULL": "/tmp/expected_full.npy",
        "PIPELINE_EXPECTED_SCALER_INPUT": "/tmp/expected_scaler_input.npy",
    })
    proc = subprocess.run(
        [sys.executable, str(PIPELINE)],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert proc.returncode == 0, f"pipeline.py failed when executed:\n{proc.stdout}"

    results = read_results()
    assert results.get("selected_features") == expected_features, (
        f"Expected selected_features to be {expected_features}, but got "
        f"{results.get('selected_features')}."
    )
    actual_mse = results.get("test_mse")
    assert isinstance(actual_mse, (int, float)), (
        f"Expected test_mse to be a number, but got {type(actual_mse).__name__}"
    )
    assert actual_mse == expected_mse, (
        f"Expected test_mse to be {expected_mse}, but got {actual_mse}."
    )

    assert EVENTS.exists(), "The required sklearn operations were not observed"
    events = [json.loads(line)["event"] for line in EVENTS.read_text().splitlines() if line]
    assert events.count("train_test_split") == 1, "train_test_split must be called exactly once"
    assert events.count("scaler_fit") == 1, "StandardScaler must be fitted exactly once on training data"
    assert events.count("linear_fit") == 1, "LinearRegression must be fitted exactly once"
    assert events.count("linear_predict") == 1, "LinearRegression must predict on the test data"


def make_probe_dataset():
    rng = np.random.default_rng(90210)
    n = 300
    values = rng.normal(size=(n, 10))
    y = 2.8 * values[:, 1] - 2.1 * values[:, 4] + rng.normal(scale=0.8, size=n)
    _, test_idx = train_test_split(np.arange(n), test_size=0.2, random_state=42)
    values[test_idx, 8] = 4.0 * y[test_idx] + rng.normal(scale=0.05, size=len(test_idx))
    df = pd.DataFrame(values, columns=[f"f{i}" for i in range(1, 11)])
    df["target"] = y

    train_features, _, _ = derive_expected(df)
    full_corr = df.drop(columns=["target"]).corrwith(df["target"])
    full_features = [name for name in df.columns[:-1] if abs(full_corr[name]) >= 0.25]
    assert train_features != ["f1", "f2", "f3"]
    assert train_features != full_features
    return df


def test_pipeline_and_results():
    assert PIPELINE.exists(), f"The required script is missing at {PIPELINE}"
    assert PIPELINE.is_file(), f"The path {PIPELINE} is not a file"
    assert stat.S_ISREG(PIPELINE.stat().st_mode), "pipeline.py must be a regular file"

    backup = Path("/tmp/original_dataset.csv")
    shutil.copy2(DATASET, backup)
    try:
        probe = make_probe_dataset()
        probe.to_csv(DATASET, index=False)
        run_and_check(probe)
    finally:
        shutil.copy2(backup, DATASET)

    original = pd.read_csv(DATASET)
    run_and_check(original)

    # Preserve the original verifier's fixed assertions for the shipped dataset.
    results = read_results()
    assert "selected_features" in results, "The key 'selected_features' is missing from results.json"
    assert "test_mse" in results, "The key 'test_mse' is missing from results.json"

    expected_features = ["f1", "f2", "f3"]
    actual_features = results["selected_features"]
    assert actual_features == expected_features, (
        f"Expected selected_features to be {expected_features}, "
        f"but got {actual_features}. Check correlation calculation and data leakage."
    )

    expected_mse = 1.0423
    actual_mse = results["test_mse"]
    assert isinstance(actual_mse, (int, float)), f"Expected test_mse to be a number, but got {type(actual_mse).__name__}"
    assert actual_mse == expected_mse, (
        f"Expected test_mse to be {expected_mse}, but got {actual_mse}. "
        "Ensure data leakage is avoided, features are scaled correctly, and MSE is rounded to 4 decimal places."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
