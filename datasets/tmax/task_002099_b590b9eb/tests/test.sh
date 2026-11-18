#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import json
import math
import os
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest
from sklearn.decomposition import PCA
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error
from sklearn.model_selection import train_test_split

SCRIPT = "/home/user/run_pipeline.py"
RESULTS = "/home/user/results.json"
INSTRUMENTATION = "/tmp/pipeline_instrumentation.json"

# Retained canonical assertions from the original verifier.
EXPECTED_MSE = 6.945229672076046
EXPECTED_PREDS = [
    0.28187834241648214,
    1.1093116467008127,
    1.071850699049448,
    -0.12920700512803875,
    -0.5694389635091218,
    0.43574163013860293,
    -0.012564245976523916,
    -0.6622431969894488,
    0.3150824883446549,
    -0.06540601550993098,
]


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def test_run_pipeline_script_exists():
    assert os.path.exists(SCRIPT), "/home/user/run_pipeline.py does not exist."
    assert os.path.isfile(SCRIPT), "/home/user/run_pipeline.py is not a file."


def test_script_structure_and_fast_inference_implementation():
    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    assert source.strip(), "/home/user/run_pipeline.py is empty."

    try:
        tree = ast.parse(source, filename=SCRIPT)
    except SyntaxError as exc:
        pytest.fail(f"run_pipeline.py is not valid Python: {exc}")

    functions = [
        node for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == "fast_inference"
    ]
    assert functions, "A fast_inference function is required."
    fn = functions[0]

    forbidden_loops = (
        ast.For, ast.AsyncFor, ast.While, ast.ListComp, ast.SetComp,
        ast.DictComp, ast.GeneratorExp,
    )
    assert not any(isinstance(node, forbidden_loops) for node in ast.walk(fn)), \
        "fast_inference must not contain Python loops or comprehensions."

    calls = [node for node in ast.walk(fn) if isinstance(node, ast.Call)]
    assert not any(
        isinstance(call.func, ast.Attribute) and call.func.attr == "predict"
        for call in calls
    ), "fast_inference must not call predict()."

    uses_matmul = any(isinstance(node, ast.BinOp) and isinstance(node.op, ast.MatMult)
                      for node in ast.walk(fn))
    uses_dot = any(
        (isinstance(call.func, ast.Attribute) and call.func.attr == "dot")
        or (isinstance(call.func, ast.Name) and call.func.id == "dot")
        for call in calls
    )
    assert uses_matmul or uses_dot, "fast_inference must use @ or dot()."

    attrs = {node.attr for node in ast.walk(fn) if isinstance(node, ast.Attribute)}
    assert "coef_" in attrs, "fast_inference must use the model's coef_."
    assert "intercept_" in attrs, "fast_inference must use the model's intercept_."

    all_calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]

    def called_name(call):
        if isinstance(call.func, ast.Name):
            return call.func.id
        if isinstance(call.func, ast.Attribute):
            return call.func.attr
        return None

    split_calls = [c for c in all_calls if called_name(c) == "train_test_split"]
    assert split_calls, "train_test_split must be used."
    assert any(
        any(k.arg == "test_size" and isinstance(k.value, ast.Constant) and k.value.value == 0.2
            for k in c.keywords)
        and any(k.arg == "random_state" and isinstance(k.value, ast.Constant) and k.value.value == 42
                for k in c.keywords)
        for c in split_calls
    ), "train_test_split must use test_size=0.2 and random_state=42."

    pca_calls = [c for c in all_calls if called_name(c) == "PCA"]
    assert any(
        any(k.arg == "n_components" and isinstance(k.value, ast.Constant) and k.value.value == 5
            for k in c.keywords)
        and any(k.arg == "random_state" and isinstance(k.value, ast.Constant) and k.value.value == 42
                for k in c.keywords)
        for c in pca_calls
    ), "PCA must use n_components=5 and random_state=42."

    ridge_calls = [c for c in all_calls if called_name(c) == "Ridge"]
    assert any(
        any(k.arg == "alpha" and isinstance(k.value, ast.Constant) and k.value.value == 1.0
            for k in c.keywords)
        and any(k.arg == "random_state" and isinstance(k.value, ast.Constant) and k.value.value == 42
                for k in c.keywords)
        for c in ridge_calls
    ), "Ridge must use alpha=1.0 and random_state=42."

    timer_names = {"perf_counter", "time", "time_ns", "process_time", "default_timer"}
    assert any(called_name(c) in timer_names for c in all_calls), \
        "The script must measure inference time with a timer."


def test_execute_pipeline_and_instrument_training_and_inference():
    data_hash_before = file_hash("/home/user/data.csv")
    for path in (RESULTS, INSTRUMENTATION):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    runner = r'''
import json
import runpy
import sys
from sklearn.decomposition import PCA

fit_rows = []
fast_calls = 0
orig_fit = PCA.fit
orig_fit_transform = PCA.fit_transform

def tracked_fit(self, X, *args, **kwargs):
    fit_rows.append(int(X.shape[0]))
    return orig_fit(self, X, *args, **kwargs)

def tracked_fit_transform(self, X, *args, **kwargs):
    fit_rows.append(int(X.shape[0]))
    return orig_fit_transform(self, X, *args, **kwargs)

def tracer(frame, event, arg):
    global fast_calls
    if event == "call" and frame.f_code.co_name == "fast_inference":
        fast_calls += 1
    return tracer

PCA.fit = tracked_fit
PCA.fit_transform = tracked_fit_transform
sys.settrace(tracer)
error = None
try:
    runpy.run_path("/home/user/run_pipeline.py", run_name="__main__")
except BaseException as exc:
    error = repr(exc)
finally:
    sys.settrace(None)
    with open("/tmp/pipeline_instrumentation.json", "w") as f:
        json.dump({"pca_fit_rows": fit_rows, "fast_calls": fast_calls, "error": error}, f)
if error is not None:
    raise RuntimeError(error)
'''
    completed = subprocess.run(
        [sys.executable, "-c", runner],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert completed.returncode == 0, f"run_pipeline.py failed:\n{completed.stdout}"
    assert file_hash("/home/user/data.csv") == data_hash_before, "The script modified data.csv."
    assert os.path.isfile(INSTRUMENTATION), "Execution instrumentation was not produced."

    with open(INSTRUMENTATION, "r") as f:
        info = json.load(f)
    assert info["error"] is None, f"run_pipeline.py raised an error: {info['error']}"
    assert info["pca_fit_rows"], "The executed script never fitted PCA."
    assert all(rows == 800 for rows in info["pca_fit_rows"]), \
        f"PCA must be fitted only on the 800-row training set; observed fits on {info['pca_fit_rows']}."
    assert info["fast_calls"] >= 100, \
        f"fast_inference must be executed at least 100 times for benchmarking; observed {info['fast_calls']}."


def test_results_json_exists():
    assert os.path.exists(RESULTS), "/home/user/results.json does not exist."
    assert os.path.isfile(RESULTS), "/home/user/results.json is not a file."


def test_results_json_content():
    with open(RESULTS, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/results.json is not a valid JSON file.")

    assert "test_mse" in results, "Key 'test_mse' is missing in results.json."
    assert "avg_inference_time_sec" in results, "Key 'avg_inference_time_sec' is missing in results.json."
    assert "predictions" in results, "Key 'predictions' is missing in results.json."

    assert isinstance(results["test_mse"], (int, float)), "'test_mse' must be a float."
    assert isinstance(results["avg_inference_time_sec"], (int, float)), \
        "'avg_inference_time_sec' must be a float."
    assert isinstance(results["predictions"], list), "'predictions' must be a list."

    assert results["avg_inference_time_sec"] > 0, \
        "'avg_inference_time_sec' must be greater than 0."
    assert math.isfinite(results["avg_inference_time_sec"]), \
        "'avg_inference_time_sec' must be finite."

    # Retain the original exact canonical checks.
    assert math.isclose(results["test_mse"], EXPECTED_MSE, rel_tol=1e-4, abs_tol=1e-4), \
        f"Expected test_mse to be close to {EXPECTED_MSE}, got {results['test_mse']}."
    preds = results["predictions"]
    assert len(preds) == 10, f"Expected 10 predictions, got {len(preds)}."
    for i, (pred, exp) in enumerate(zip(preds, EXPECTED_PREDS)):
        assert isinstance(pred, (int, float)), f"Prediction at index {i} is not a float."
        assert math.isclose(pred, exp, rel_tol=1e-4, abs_tol=1e-4), \
            f"Prediction at index {i} expected to be close to {exp}, got {pred}."

    # Independently derive the required answers from the supplied dataset.
    df = pd.read_csv("/home/user/data.csv")
    X = df.drop(columns=["y"])
    y = df["y"]
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    pca = PCA(n_components=5, random_state=42)
    X_train_t = pca.fit_transform(X_train)
    X_test_t = pca.transform(X_test)
    model = Ridge(alpha=1.0, random_state=42)
    model.fit(X_train_t, y_train)
    expected_predictions = X_test_t @ model.coef_ + model.intercept_
    expected_mse = mean_squared_error(y_test, expected_predictions)

    assert math.isclose(results["test_mse"], float(expected_mse), rel_tol=1e-7, abs_tol=1e-7)
    assert np.allclose(
        np.asarray(preds, dtype=float), expected_predictions[:10], rtol=1e-7, atol=1e-7
    ), "Predictions do not match an independently fitted leakage-free pipeline."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
