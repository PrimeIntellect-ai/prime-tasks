#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import importlib.util
import json
import math
import os
import secrets
import subprocess

import numpy as np
import pandas as pd
import pytest
from scipy.optimize import curve_fit


def load_optimizer():
    path = "/home/user/optimizer.py"
    assert os.path.isfile(path), f"{path} is missing."
    spec = importlib.util.spec_from_file_location("submitted_optimizer", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "fit_exponential"), "optimizer.py does not define fit_exponential."
    assert callable(module.fit_exponential), "fit_exponential is not callable."
    return module


def unpack_params(result):
    if isinstance(result, dict):
        assert "A" in result and "B" in result, "fit_exponential result must contain A and B."
        A, B = result["A"], result["B"]
    else:
        try:
            A, B = result
        except Exception as exc:
            pytest.fail(f"fit_exponential must return two parameters A and B: {exc}")
    A, B = float(A), float(B)
    assert math.isfinite(A) and math.isfinite(B), "Fitted parameters must be finite."
    assert A > 0 and B > 0, "Fitted parameters must be positive."
    return A, B


def test_processed_data_csv():
    file_path = "/home/user/processed_data.csv"
    assert os.path.isfile(file_path), f"{file_path} is missing."

    with open(file_path, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, f"{file_path} is empty."
    header = rows[0]
    assert header == ["timestamp", "feature_alpha", "feature_beta"], f"Incorrect header in {file_path}: {header}"

    expected_data = [
        ["1", "0.0", "5.0"],
        ["2", "1.0", "3.03265"],
        ["3", "2.0", "1.8394"],
        ["4", "3.0", "1.11565"],
        ["5", "4.0", "0.67668"],
    ]

    data_rows = rows[1:]
    assert len(data_rows) == len(expected_data), f"Expected {len(expected_data)} data rows, but got {len(data_rows)}."

    for i, expected in enumerate(expected_data):
        assert float(data_rows[i][0]) == float(expected[0]), f"Row {i+1} timestamp mismatch."
        assert float(data_rows[i][1]) == float(expected[1]), f"Row {i+1} feature_alpha mismatch."
        assert abs(float(data_rows[i][2]) - float(expected[2])) < 1e-4, f"Row {i+1} feature_beta mismatch."


def test_params_json():
    file_path = "/home/user/params.json"
    assert os.path.isfile(file_path), f"{file_path} is missing."

    with open(file_path, "r") as f:
        try:
            params = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{file_path} is not valid JSON.")

    assert "A" in params, "Key 'A' missing in params.json."
    assert "B" in params, "Key 'B' missing in params.json."
    assert 4.95 <= params["A"] <= 5.05, f"Value of A ({params['A']}) is outside expected range [4.95, 5.05]."
    assert 0.45 <= params["B"] <= 0.55, f"Value of B ({params['B']}) is outside expected range [0.45, 0.55]."


def test_python_files_exist():
    assert os.path.isfile("/home/user/optimizer.py"), "/home/user/optimizer.py is missing."
    assert os.path.isfile("/home/user/test_optimization.py"), "/home/user/test_optimization.py is missing."


def test_pytest_runs_successfully():
    test_file = "/home/user/test_optimization.py"
    assert os.path.isfile(test_file), f"{test_file} is missing."
    result = subprocess.run(["pytest", test_file], capture_output=True, text=True)
    assert result.returncode == 0, f"pytest failed on {test_file}. Output:\n{result.stdout}\n{result.stderr}"


def test_optimizer_uses_required_scipy_api():
    path = "/home/user/optimizer.py"
    with open(path, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=path)

    scipy_imported = any(
        (isinstance(node, ast.Import) and any(alias.name.startswith("scipy") for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and (node.module or "").startswith("scipy"))
        for node in ast.walk(tree)
    )
    called_names = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Name):
                called_names.append(func.id)
            elif isinstance(func, ast.Attribute):
                called_names.append(func.attr)

    assert scipy_imported, "optimizer.py must import scipy optimization functionality."
    assert any(name in {"minimize", "curve_fit"} for name in called_names), \
        "optimizer.py must call scipy.optimize.minimize or scipy.optimize.curve_fit."


def test_fit_exponential_on_unseen_inputs():
    module = load_optimizer()
    rng = secrets.SystemRandom()

    for _ in range(4):
        expected_A = rng.uniform(1.4, 6.0)
        expected_B = rng.uniform(0.15, 0.9)
        x = np.array([0.0, 0.2, 0.65, 1.15, 1.9, 2.8, 3.7], dtype=float)
        y = expected_A * np.exp(-expected_B * x)
        df = pd.DataFrame({"timestamp": range(len(x)), "feature_alpha": x, "feature_beta": y})

        actual_A, actual_B = unpack_params(module.fit_exponential(df))
        assert abs(actual_A - expected_A) < 0.01, \
            f"Incorrect A for unseen exponential data: expected {expected_A}, got {actual_A}."
        assert abs(actual_B - expected_B) < 0.01, \
            f"Incorrect B for unseen exponential data: expected {expected_B}, got {actual_B}."


def test_saved_params_match_real_fit():
    module = load_optimizer()
    df = pd.read_csv("/home/user/processed_data.csv")
    actual_A, actual_B = unpack_params(module.fit_exponential(df))

    x = df["feature_alpha"].to_numpy(dtype=float)
    y = df["feature_beta"].to_numpy(dtype=float)
    expected, _ = curve_fit(lambda values, A, B: A * np.exp(-B * values), x, y, p0=(5.0, 0.5), bounds=(0, np.inf))
    assert abs(actual_A - expected[0]) < 0.01
    assert abs(actual_B - expected[1]) < 0.01

    with open("/home/user/params.json", "r", encoding="utf-8") as f:
        saved = json.load(f)
    assert abs(float(saved["A"]) - actual_A) < 0.01, "params.json A does not match fit_exponential output."
    assert abs(float(saved["B"]) - actual_B) < 0.01, "params.json B does not match fit_exponential output."


def test_regression_test_exercises_required_case():
    path = "/home/user/test_optimization.py"
    with open(path, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=path)

    calls_fit = any(
        isinstance(node, ast.Call)
        and ((isinstance(node.func, ast.Name) and node.func.id == "fit_exponential")
             or (isinstance(node.func, ast.Attribute) and node.func.attr == "fit_exponential"))
        for node in ast.walk(tree)
    )
    constants = {float(node.value) for node in ast.walk(tree)
                 if isinstance(node, ast.Constant) and isinstance(node.value, (int, float))}
    assert calls_fit, "The regression test must call fit_exponential."
    assert len([node for node in ast.walk(tree) if isinstance(node, ast.Assert)]) >= 2, \
        "The regression test must assert both fitted parameters."
    assert {0.0, 1.0, 2.0, 2.5, 0.5}.issubset(constants), \
        "The regression test must include the prescribed synthetic exponential case."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
