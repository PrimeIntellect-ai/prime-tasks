#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def solve_tridiagonal(a, b, c, d):
    n = len(d)
    c_prime = [0.0] * n
    d_prime = [0.0] * n

    c_prime[0] = c[0] / b[0]
    d_prime[0] = d[0] / b[0]

    for i in range(1, n):
        denom = b[i] - a[i] * c_prime[i-1]
        if i < n - 1:
            c_prime[i] = c[i] / denom
        d_prime[i] = (d[i] - a[i] * d_prime[i-1]) / denom

    x = [0.0] * n
    x[n-1] = d_prime[n-1]
    for i in range(n-2, -1, -1):
        x[i] = d_prime[i] - c_prime[i] * x[i+1]
    return x

def compute_expected():
    nt = 11
    nx = 11
    u = [[0.0]*nx for _ in range(nt)]
    for n in range(nt):
        u[n][nx-1] = 100.0

    a = [-0.5] * 9
    b = [2.0] * 9
    c = [-0.5] * 9

    for n in range(nt - 1):
        d = u[n][1:10].copy()
        d[-1] += 0.5 * 100.0

        u_next = solve_tridiagonal(a, b, c, d)
        for i in range(9):
            u[n+1][i+1] = u_next[i]

    return u

def test_go_file_exists():
    assert os.path.isfile("/home/user/simulate_heat.go"), "The Go source file /home/user/simulate_heat.go does not exist."

def test_json_output_exists():
    assert os.path.isfile("/home/user/heat_results.json"), "The output file /home/user/heat_results.json does not exist."

def test_json_results_correctness():
    with open("/home/user/heat_results.json", "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file /home/user/heat_results.json is not valid JSON.")

    assert isinstance(results, list), "The JSON root should be a list (2D array)."
    assert len(results) == 11, f"Expected 11 time steps, got {len(results)}."
    for n, row in enumerate(results):
        assert isinstance(row, list), f"Row {n} is not a list."
        assert len(row) == 11, f"Expected 11 spatial points at time step {n}, got {len(row)}."

    expected = compute_expected()

    # Check specific boundary and initial conditions
    assert math.isclose(results[0][5], 0.0, abs_tol=1e-5), "Initial condition at interior point is incorrect."
    assert math.isclose(results[10][0], 0.0, abs_tol=1e-5), "Boundary condition at x=0 is incorrect."
    assert math.isclose(results[10][10], 100.0, abs_tol=1e-5), "Boundary condition at x=1 is incorrect."

    # Check key computation points
    assert math.isclose(results[1][9], expected[1][9], rel_tol=1e-3, abs_tol=1e-3), f"Value at n=1, i=9 is incorrect. Expected ~{expected[1][9]}, got {results[1][9]}"
    assert math.isclose(results[10][5], expected[10][5], rel_tol=1e-3, abs_tol=1e-3), f"Value at n=10, i=5 is incorrect. Expected ~{expected[10][5]}, got {results[10][5]}"

    # Full matrix check
    for n in range(11):
        for i in range(11):
            assert math.isclose(results[n][i], expected[n][i], rel_tol=1e-3, abs_tol=1e-3), f"Mismatch at n={n}, i={i}. Expected {expected[n][i]}, got {results[n][i]}."
TEST_EOF

rm -f /home/user/heat_results.json /tmp/simulate_heat_verifier
if go build -o /tmp/simulate_heat_verifier /home/user/simulate_heat.go 2>&1 \
   && timeout 30s /tmp/simulate_heat_verifier 2>&1 \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
