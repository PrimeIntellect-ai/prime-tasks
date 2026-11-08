#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import subprocess
import sys

import numpy as np
import pytest
from scipy.sparse import lil_matrix
from scipy.sparse.linalg import spsolve
from scipy.stats import shapiro

RESULTS_PATH = "/home/user/results.json"
SCRIPT_PATH = "/home/user/solve.py"
EXPECTED_KEYS = {
    "E_10", "E_20", "E_40", "p_1", "p_2",
    "shapiro_statistic", "shapiro_p_value"
}


def analytical(x, y):
    return np.sin(np.pi * x) * np.sinh(np.pi * y)


def reference_solution(N):
    h = 1.0 / N
    n = N - 1
    A = lil_matrix((n * n, n * n), dtype=float)
    b = np.zeros(n * n, dtype=float)

    def index(i, j):
        return (i - 1) * n + (j - 1)

    for i in range(1, N):
        x = i * h
        for j in range(1, N):
            y = j * h
            k = index(i, j)
            A[k, k] = 4.0

            if i > 1:
                A[k, index(i - 1, j)] = -1.0
            else:
                b[k] += analytical(0.0, y)
            if i < N - 1:
                A[k, index(i + 1, j)] = -1.0
            else:
                b[k] += analytical(1.0, y)
            if j > 1:
                A[k, index(i, j - 1)] = -1.0
            else:
                b[k] += analytical(x, 0.0)
            if j < N - 1:
                A[k, index(i, j + 1)] = -1.0
            else:
                b[k] += analytical(x, 1.0)

    interior = spsolve(A.tocsr(), b)
    coords = np.linspace(0.0, 1.0, N + 1)
    X, Y = np.meshgrid(coords, coords, indexing="ij")
    exact = analytical(X, Y)
    numerical = exact.copy()
    for i in range(1, N):
        for j in range(1, N):
            numerical[i, j] = interior[index(i, j)]

    errors = numerical - exact
    return float(np.max(np.abs(errors))), errors.ravel()


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.exists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file."
    if os.path.lexists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    try:
        completed = subprocess.run(
            ["runuser", "-u", "user", "--", sys.executable, SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("solve.py did not finish within 180 seconds.")
    assert completed.returncode == 0, (
        f"solve.py exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


@pytest.fixture(scope="session")
def reference_results():
    E10, _ = reference_solution(10)
    E20, _ = reference_solution(20)
    E40, errors40 = reference_solution(40)
    statistic, p_value = shapiro(errors40)
    return {
        "E_10": E10,
        "E_20": E20,
        "E_40": E40,
        "p_1": math.log2(E10 / E20),
        "p_2": math.log2(E20 / E40),
        "shapiro_statistic": float(statistic),
        "shapiro_p_value": float(p_value),
    }


def load_results():
    with open(RESULTS_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} is not valid JSON.")


def test_results_file_exists():
    assert os.path.exists(RESULTS_PATH), f"Results file {RESULTS_PATH} does not exist."
    assert os.path.isfile(RESULTS_PATH), f"{RESULTS_PATH} is not a file."


def test_results_json_structure():
    data = load_results()
    actual_keys = set(data.keys())
    missing_keys = EXPECTED_KEYS - actual_keys
    extra_keys = actual_keys - EXPECTED_KEYS
    assert not missing_keys, f"Missing keys in results.json: {missing_keys}"
    assert not extra_keys, f"Extra keys in results.json: {extra_keys}"
    for key in EXPECTED_KEYS:
        val = data[key]
        assert isinstance(val, (int, float)) and not isinstance(val, bool), \
            f"Value for {key} must be a number, got {type(val)}."
        assert math.isfinite(val), f"Value for {key} must be finite."


def test_results_values_plausible():
    data = load_results()
    E_10 = data["E_10"]
    E_20 = data["E_20"]
    E_40 = data["E_40"]
    p_1 = data["p_1"]
    p_2 = data["p_2"]
    stat = data["shapiro_statistic"]
    pval = data["shapiro_p_value"]

    assert E_10 > 0, "Max error E_10 should be positive."
    assert E_20 > 0, "Max error E_20 should be positive."
    assert E_40 > 0, "Max error E_40 should be positive."
    assert E_10 > E_20 > E_40, "Errors should decrease as N increases."
    assert 1.8 < p_1 < 2.2, f"Convergence order p_1={p_1} is far from expected ~2.0."
    assert 1.8 < p_2 < 2.2, f"Convergence order p_2={p_2} is far from expected ~2.0."
    assert 0.0 <= stat <= 1.0, f"Shapiro-Wilk statistic {stat} must be between 0 and 1."
    assert 0.0 <= pval <= 1.0, f"Shapiro-Wilk p-value {pval} must be between 0 and 1."


def test_results_match_independent_solution(reference_results):
    data = load_results()
    for key, expected in reference_results.items():
        assert data[key] == pytest.approx(round(expected, 6), abs=5e-7, rel=0), \
            f"{key}={data[key]} does not match the independently computed value {expected}."


def test_orders_are_consistent_with_reported_errors():
    data = load_results()
    p1_from_errors = math.log2(data["E_10"] / data["E_20"])
    p2_from_errors = math.log2(data["E_20"] / data["E_40"])
    assert data["p_1"] == pytest.approx(p1_from_errors, abs=5e-4, rel=0)
    assert data["p_2"] == pytest.approx(p2_from_errors, abs=5e-4, rel=0)


def test_results_rounding():
    with open(RESULTS_PATH, "r") as f:
        content = f.read()
        data = json.loads(content)
    for key, val in data.items():
        rounded_val = round(val, 6)
        assert math.isclose(val, rounded_val, rel_tol=1e-9, abs_tol=1e-9), \
            f"Value for {key} ({val}) does not appear to be rounded to 6 decimal places."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
