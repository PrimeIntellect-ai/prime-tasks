#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import runpy
import subprocess

import numpy as np
import pandas as pd
import pytest
from scipy.optimize import curve_fit

SCRIPT_PATH = "/home/user/prepare_data.py"
DATA_PATH = "/home/user/raw_battery_data.csv"
OUTPUT_PATH = "/home/user/degradation_metadata.json"


def test_prepare_data_script_exists_and_runs():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a file."

    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    compile(source, SCRIPT_PATH, "exec")

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"Running {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_seed_is_set_exactly_once_immediately_before_bootstrap_loop():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=SCRIPT_PATH)

    seed_calls = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if (isinstance(func, ast.Attribute) and func.attr == "seed") or (
            isinstance(func, ast.Name) and func.id == "seed"
        ):
            seed_calls.append(node)

    assert len(seed_calls) == 1, "numpy.random.seed must be called exactly once."
    seed_call = seed_calls[0]
    assert len(seed_call.args) == 1 and isinstance(seed_call.args[0], ast.Constant) and seed_call.args[0].value == 42, (
        "The single random seed call must be numpy.random.seed(42)."
    )

    containing_statement = None
    following_statement = None
    for parent in ast.walk(tree):
        for _, value in ast.iter_fields(parent):
            if not isinstance(value, list):
                continue
            for index, statement in enumerate(value):
                if isinstance(statement, ast.stmt) and seed_call in set(ast.walk(statement)):
                    containing_statement = statement
                    if index + 1 < len(value):
                        following_statement = value[index + 1]
                    break
            if containing_statement is not None:
                break
        if containing_statement is not None:
            break

    assert containing_statement is not None, "Could not locate the seed call as a statement."
    assert isinstance(following_statement, (ast.For, ast.AsyncFor, ast.While)), (
        "numpy.random.seed(42) must appear immediately before the bootstrap loop."
    )


def test_metadata_file_exists():
    """Test that the degradation_metadata.json file was created."""
    file_path = "/home/user/degradation_metadata.json"
    assert os.path.exists(file_path), f"The output file {file_path} is missing."
    assert os.path.isfile(file_path), f"The path {file_path} exists but is not a file."


def test_metadata_structure_and_types():
    """Test that the metadata JSON has the exact required keys and float values."""
    file_path = "/home/user/degradation_metadata.json"
    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} is not valid JSON.")

    expected_keys = {"a", "b", "c", "b_ci_lower", "b_ci_upper"}
    assert set(data.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}, but found {set(data.keys())}."

    for key in expected_keys:
        assert isinstance(data[key], (int, float)), f"Value for '{key}' must be a number."


def test_metadata_values_plausible():
    """Test that the fitted parameters are close to the expected true parameters."""
    file_path = "/home/user/degradation_metadata.json"
    with open(file_path, 'r') as f:
        data = json.load(f)

    # True parameters are approximately a=1.5, b=0.005, c=0.2
    assert 1.0 < data["a"] < 2.0, f"Parameter 'a' ({data['a']}) is outside the expected range."
    assert 0.001 < data["b"] < 0.01, f"Parameter 'b' ({data['b']}) is outside the expected range."
    assert 0.0 < data["c"] < 0.5, f"Parameter 'c' ({data['c']}) is outside the expected range."

    assert data["b_ci_lower"] < data["b"], "b_ci_lower should be less than the estimate of b."
    assert data["b_ci_upper"] > data["b"], "b_ci_upper should be greater than the estimate of b."
    assert data["b_ci_lower"] > 0, "b_ci_lower should be positive."
    assert data["b_ci_upper"] < 0.02, "b_ci_upper is unexpectedly large."


def test_script_recomputes_fit_and_seeded_1000_iteration_bootstrap(monkeypatch):
    with open(DATA_PATH, "rb") as f:
        original_csv = f.read()
    with open(OUTPUT_PATH, "rb") as f:
        original_metadata = f.read()

    def model(x, a, b, c):
        return a * np.exp(-b * x) + c

    rng = np.random.default_rng(20260911)
    x = np.linspace(7.0, 430.0, 120)
    y = 1.18 * np.exp(-0.0074 * x) + 0.31 + rng.normal(0.0, 0.014, size=x.size)

    expected_params, _ = curve_fit(model, x, y, p0=[1.0, 0.01, 0.5])
    np.random.seed(42)
    expected_bootstrap_b = []
    for _ in range(1000):
        indices = np.random.choice(len(x), size=len(x), replace=True)
        fitted, _ = curve_fit(model, x[indices], y[indices], p0=[1.0, 0.01, 0.5])
        expected_bootstrap_b.append(float(fitted[1]))
    expected_lower, expected_upper = np.percentile(expected_bootstrap_b, [2.5, 97.5])

    seed_calls = []
    real_seed = np.random.seed

    def recording_seed(*args, **kwargs):
        seed_calls.append((args, kwargs))
        return real_seed(*args, **kwargs)

    try:
        pd.DataFrame({"cycle": x, "capacity": y}).to_csv(DATA_PATH, index=False)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        monkeypatch.setattr(np.random, "seed", recording_seed)
        runpy.run_path(SCRIPT_PATH, run_name="__main__")

        assert seed_calls == [((42,), {})], (
            "Execution must call numpy.random.seed(42) exactly once before bootstrapping."
        )
        assert os.path.isfile(OUTPUT_PATH), "The executed script did not create the metadata JSON."

        with open(OUTPUT_PATH, "r") as f:
            actual = json.load(f)

        assert set(actual) == {"a", "b", "c", "b_ci_lower", "b_ci_upper"}
        actual_values = np.array([
            actual["a"], actual["b"], actual["c"],
            actual["b_ci_lower"], actual["b_ci_upper"],
        ], dtype=float)
        expected_values = np.array([
            expected_params[0], expected_params[1], expected_params[2],
            expected_lower, expected_upper,
        ], dtype=float)
        assert np.all(np.isfinite(actual_values)), "All output values must be finite."
        assert np.allclose(actual_values, expected_values, rtol=2e-6, atol=2e-9), (
            "The script's results do not match a fit on the supplied data followed by the "
            "required numpy-seeded, exactly 1000-iteration bootstrap.\n"
            f"Expected: {expected_values.tolist()}\nActual: {actual_values.tolist()}"
        )
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_csv)
        with open(OUTPUT_PATH, "wb") as f:
            f.write(original_metadata)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
