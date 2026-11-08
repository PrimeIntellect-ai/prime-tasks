#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import subprocess
import sys

import pytest

SCRIPT = "/home/user/run_sim.py"
RESULTS = "/home/user/sim_results.json"
NS = [10, 50, 100, 200]


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT), "The script /home/user/run_sim.py does not exist."
    if os.path.exists(RESULTS):
        os.remove(RESULTS)

    completed = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert completed.returncode == 0, (
        "run_sim.py failed when executed.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )


def thomas_solve(n, diagonal, off_diagonal, rhs):
    c_prime = [0.0] * n
    d_prime = [0.0] * n
    c_prime[0] = off_diagonal / diagonal
    d_prime[0] = rhs[0] / diagonal

    for i in range(1, n):
        denominator = diagonal - off_diagonal * c_prime[i - 1]
        if i < n - 1:
            c_prime[i] = off_diagonal / denominator
        d_prime[i] = (rhs[i] - off_diagonal * d_prime[i - 1]) / denominator

    solution = [0.0] * n
    solution[-1] = d_prime[-1]
    for i in range(n - 2, -1, -1):
        solution[i] = d_prime[i] - c_prime[i] * solution[i + 1]
    return solution


def independently_expected(n):
    h = 1.0 / (n + 1)

    # Exact extremal eigenvalues of the scaled negative-Laplacian matrix.
    angle = math.pi / (2.0 * (n + 1))
    condition_number = (math.cos(angle) / math.sin(angle)) ** 2

    # sin(pi*x_i) is an eigenvector of the finite-difference matrix.
    discrete_eigenvalue = 4.0 * math.sin(math.pi * h / 2.0) ** 2 / (h * h)
    amplitude_error = abs(1.0 / discrete_eigenvalue - 1.0 / (math.pi ** 2))
    max_sine = max(abs(math.sin(math.pi * i * h)) for i in range(1, n + 1))
    clean_error = amplitude_error * max_sine

    diagonal = 2.0 / (h * h)
    off_diagonal = -1.0 / (h * h)
    perturbation = [1.0e-6 * ((-1.0) ** i) for i in range(1, n + 1)]
    response = thomas_solve(n, diagonal, off_diagonal, perturbation)
    perturbed_diff = max(abs(value) for value in response)

    return {
        "condition_number": condition_number,
        "clean_error": clean_error,
        "perturbed_diff": perturbed_diff,
    }


def test_run_sim_script_exists():
    assert os.path.isfile(SCRIPT), "The script /home/user/run_sim.py does not exist."


def test_script_contains_required_numerical_operations():
    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    assert source.strip(), "run_sim.py is empty."

    try:
        tree = ast.parse(source, filename=SCRIPT)
    except SyntaxError as exc:
        pytest.fail(f"run_sim.py is not valid Python: {exc}")

    called_names = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Name):
            called_names.append(func.id.lower())
        elif isinstance(func, ast.Attribute):
            called_names.append(func.attr.lower())

    assert "svd" in called_names, "run_sim.py must calculate the condition number using SVD."
    assert any(name in {"cholesky", "cho_factor"} for name in called_names), (
        "run_sim.py must compute a Cholesky decomposition."
    )


def test_sim_results_exists():
    assert os.path.isfile(RESULTS), (
        "Executing run_sim.py did not generate /home/user/sim_results.json."
    )


def test_sim_results_content():
    with open(RESULTS, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file /home/user/sim_results.json is not a valid JSON file.")

    expected_keys = ["10", "50", "100", "200"]
    for key in expected_keys:
        assert key in data, f"Key '{key}' is missing from the JSON output."

    for n in NS:
        n_str = str(n)
        expected = independently_expected(n)
        actual = data[n_str]
        assert isinstance(actual, dict), f"Value for N={n_str} must be an object."

        for metric in ["condition_number", "clean_error", "perturbed_diff"]:
            assert metric in actual, f"Metric '{metric}' missing for N={n_str}"
            actual_val = actual[metric]
            assert isinstance(actual_val, (int, float)) and not isinstance(actual_val, bool), (
                f"Value for {metric} at N={n_str} must be numeric."
            )
            assert math.isfinite(actual_val), (
                f"Value for {metric} at N={n_str} must be finite."
            )

            expected_val = expected[metric]
            rel_error = abs(actual_val - expected_val) / expected_val
            assert rel_error < 0.05, (
                f"Value for {metric} at N={n_str} is {actual_val}, "
                f"expected approximately {expected_val}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
