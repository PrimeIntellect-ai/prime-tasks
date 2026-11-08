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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
from pathlib import Path
import random
import subprocess
import sys

import numpy as np
import pytest
import requests

URL = "http://127.0.0.1:8080/simulate"
GOOD_HEADERS = {"Authorization": "Bearer sim_token_99"}
INTEGRATOR = Path("/app/mol_sim_net-1.0.0/mol_sim_net/integrator.py")


def matrix_mult(A, B):
    rows_A = len(A)
    cols_A = len(A[0])
    cols_B = len(B[0])
    C = [[0.0] * cols_B for _ in range(rows_A)]
    for i in range(rows_A):
        for j in range(cols_B):
            for k in range(cols_A):
                C[i][j] += A[i][k] * B[k][j]
    return C


def matrix_add(A, B):
    return [[A[i][j] + B[i][j] for j in range(len(A[0]))] for i in range(len(A))]


def matrix_scale(A, scalar):
    return [[A[i][j] * scalar for j in range(len(A[0]))] for i in range(len(A))]


def eye(n):
    return [[1.0 if i == j else 0.0 for j in range(n)] for i in range(n)]


def matrix_exp(A, terms=50):
    n = len(A)
    result = eye(n)
    term = eye(n)
    for i in range(1, terms):
        term = matrix_mult(term, A)
        term = matrix_scale(term, 1.0 / i)
        result = matrix_add(result, term)
    return result


def laplacian(n, edges):
    L = np.zeros((n, n), dtype=float)
    for u, v in edges:
        L[u, u] += 1.0
        L[v, v] += 1.0
        L[u, v] -= 1.0
        L[v, u] -= 1.0
    return L


def exact_solution(L, x0, t_end):
    values, vectors = np.linalg.eigh(L)
    return vectors @ (np.exp(-values * t_end) * (vectors.T @ np.asarray(x0, dtype=float)))


def post(payload, headers=GOOD_HEADERS, timeout=12):
    try:
        return requests.post(URL, json=payload, headers=headers, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Could not complete request to {URL}: {exc}")


def test_unauthorized():
    payload = {
        "edges": [[0, 1], [0, 2], [0, 3]],
        "initial_state": [1.0, 0.0, 0.0, 0.0],
        "t_end": 2.0,
        "tol": 1e-4,
    }

    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the server at 127.0.0.1:8080. Is it running?")
    assert response.status_code == 401, f"Expected 401 Unauthorized for missing token, got {response.status_code}"

    response = requests.post(
        URL,
        json=payload,
        headers={"Authorization": "Bearer wrong_token"},
        timeout=5,
    )
    assert response.status_code == 401, f"Expected 401 Unauthorized for incorrect token, got {response.status_code}"


def test_original_simulate_endpoint():
    payload = {
        "edges": [[0, 1], [0, 2], [0, 3]],
        "initial_state": [1.0, 0.0, 0.0, 0.0],
        "t_end": 2.0,
        "tol": 1e-4,
    }

    try:
        response = requests.post(URL, json=payload, headers=GOOD_HEADERS, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the server at 127.0.0.1:8080. Is it running?")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "final_state" in data, "Response JSON missing 'final_state' key"
    final_state = data["final_state"]
    assert isinstance(final_state, list), "'final_state' must be a list"
    assert len(final_state) == 4, "'final_state' must have 4 elements"

    L = [[3.0, -1.0, -1.0, -1.0],
         [-1.0, 1.0, 0.0, 0.0],
         [-1.0, 0.0, 1.0, 0.0],
         [-1.0, 0.0, 0.0, 1.0]]
    minus_Lt = matrix_scale(L, -2.0)
    exp_minus_Lt = matrix_exp(minus_Lt, terms=100)
    true_final_state_col = matrix_mult(exp_minus_Lt, [[1.0], [0.0], [0.0], [0.0]])
    true_final_state = [row[0] for row in true_final_state_col]

    for i in range(4):
        assert abs(final_state[i] - true_final_state[i]) <= 1e-3, \
            f"Element {i} mismatch: expected {true_final_state[i]:.4f}, got {final_state[i]:.4f}"


def test_vendored_integrator_exists_and_converges_on_varied_stiff_graphs():
    assert INTEGRATOR.is_file(), f"Required vendored integrator is missing: {INTEGRATOR}"
    source = INTEGRATOR.read_text()
    assert "def integrate_diffusion" in source, "Vendored integrator does not define integrate_diffusion"
    assert "dt_new" in source, "Vendored integrator does not contain adaptive step-size logic"

    rng = random.SystemRandom()
    cases = []
    for n in (6, 8):
        edges = [[i, j] for i in range(n) for j in range(i + 1, n)]
        L = laplacian(n, edges)
        x0 = [rng.uniform(-0.8, 1.7) for _ in range(n)]
        t_end = rng.uniform(0.25, 0.65)
        cases.append({"L": L.tolist(), "x0": x0, "t_end": t_end, "tol": 1e-6})

    runner = r'''
import importlib.util, json, pathlib, sys
path = pathlib.Path("/app/mol_sim_net-1.0.0/mol_sim_net/integrator.py")
spec = importlib.util.spec_from_file_location("audited_vendored_integrator", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert pathlib.Path(module.__file__).resolve() == path.resolve()
cases = json.loads(sys.stdin.read())
out = [module.integrate_diffusion(c["L"], c["x0"], c["t_end"], c["tol"]) for c in cases]
print(json.dumps(out))
'''
    try:
        completed = subprocess.run(
            [sys.executable, "-c", runner],
            input=json.dumps(cases),
            text=True,
            capture_output=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The vendored adaptive integrator did not converge within 15 seconds")

    assert completed.returncode == 0, \
        f"Vendored integrator failed when executed directly:\n{completed.stderr}"
    try:
        outputs = json.loads(completed.stdout.strip().splitlines()[-1])
    except Exception as exc:
        pytest.fail(f"Vendored integrator did not produce valid results: {exc}; stdout={completed.stdout!r}")

    assert len(outputs) == len(cases)
    for case, output in zip(cases, outputs):
        expected = exact_solution(np.asarray(case["L"]), case["x0"], case["t_end"])
        actual = np.asarray(output, dtype=float)
        assert actual.shape == expected.shape
        assert np.all(np.isfinite(actual)), "Vendored integrator returned NaN or infinity"
        assert np.max(np.abs(actual - expected)) <= 1e-3, \
            f"Vendored integrator is inaccurate: expected {expected}, got {actual}"
        assert abs(float(actual.sum()) - sum(case["x0"])) <= 1e-8, \
            "Diffusion integration did not conserve total concentration"


def test_simulate_varied_runtime_inputs():
    rng = random.SystemRandom()
    cases = []

    # A randomly parameterized dense graph exercises the stiff case.
    n = rng.randrange(5, 9)
    complete_edges = [[i, j] for i in range(n) for j in range(i + 1, n)]
    cases.append((n, complete_edges))

    # A non-symmetric connected topology prevents a response specialized to one graph family.
    n2 = rng.randrange(5, 9)
    sparse_edges = [[i, i + 1] for i in range(n2 - 1)]
    for i in range(n2):
        for j in range(i + 2, n2):
            if rng.random() < 0.3:
                sparse_edges.append([i, j])
    cases.append((n2, sparse_edges))

    for node_count, edges in cases:
        initial = [rng.uniform(-0.5, 2.0) for _ in range(node_count)]
        t_end = rng.uniform(0.15, 0.9)
        tol = rng.choice([1e-6, 2e-6, 5e-6])
        payload = {
            "edges": edges,
            "initial_state": initial,
            "t_end": t_end,
            "tol": tol,
        }
        response = post(payload)
        assert response.status_code == 200, \
            f"Expected 200 OK for varied input, got {response.status_code}: {response.text}"
        data = response.json()
        assert "final_state" in data, "Response JSON missing 'final_state' key"
        actual = data["final_state"]
        assert isinstance(actual, list), "'final_state' must be a list"
        assert len(actual) == node_count, \
            f"Expected {node_count} output elements, got {len(actual)}"
        assert all(isinstance(v, (int, float)) and math.isfinite(v) for v in actual), \
            "All final_state values must be finite numbers"

        expected = exact_solution(laplacian(node_count, edges), initial, t_end)
        expected_rounded = np.round(expected, 4)
        assert np.max(np.abs(np.asarray(actual, dtype=float) - expected_rounded)) <= 1.5e-3, \
            f"Incorrect simulation for runtime-generated input: expected {expected_rounded}, got {actual}"
        assert all(abs(float(v) - round(float(v), 4)) <= 1e-9 for v in actual), \
            "final_state values must be rounded to 4 decimal places"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
