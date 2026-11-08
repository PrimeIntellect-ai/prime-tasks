#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math

def compute_expected_values():
    # Discretization
    n_points = 10000
    x = [-5.0 + 10.0 * i / (n_points - 1) for i in range(n_points)]

    def trapezoid(y, x):
        s = 0.0
        for i in range(len(x) - 1):
            s += (y[i] + y[i+1]) * 0.5 * (x[i+1] - x[i])
        return s

    def V(c):
        w = [math.exp(-c * xi**2 - xi**4) for xi in x]
        Z = trapezoid(w, x)
        P = [wi / Z for wi in w]
        x2P = [xi**2 * Pi for xi, Pi in zip(x, P)]
        return trapezoid(x2P, x)

    # 1. Bisection to find c_star where V(c) = 0.25
    low, high = 0.0, 5.0
    for _ in range(60):
        mid = (low + high) / 2.0
        # V(c) is decreasing with c
        if V(mid) > 0.25:
            low = mid
        else:
            high = mid
    c_star = (low + high) / 2.0

    # 2. Derivative V'(c_star)
    h = 1e-4
    v_plus = V(c_star + h)
    v_minus = V(c_star - h)
    v_prime = (v_plus - v_minus) / (2.0 * h)

    # 3. KL Divergence
    w_star = [math.exp(-c_star * xi**2 - xi**4) for xi in x]
    Z_star = trapezoid(w_star, x)
    p = [wi / Z_star for wi in w_star]

    q = [(1.0 / math.sqrt(2 * math.pi * 0.25)) * math.exp(-xi**2 / (2 * 0.25)) for xi in x]

    sum_p = sum(p)
    sum_q = sum(q)

    p_hat = [pi / sum_p for pi in p]
    q_hat = [qi / sum_q for qi in q]

    kl_div = 0.0
    for pi, qi in zip(p_hat, q_hat):
        if pi > 0 and qi > 0:
            kl_div += pi * math.log(pi / qi)

    return c_star, v_prime, kl_div

def test_results_json_exists():
    assert os.path.exists("/home/user/results.json"), "Output file /home/user/results.json does not exist."

def test_results_json_contents():
    results_path = "/home/user/results.json"
    assert os.path.exists(results_path), f"File {results_path} not found."

    with open(results_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "File /home/user/results.json is not valid JSON."

    expected_c_star, expected_v_prime, expected_kl = compute_expected_values()

    assert "c_star" in data, "Key 'c_star' missing from results.json."
    assert "variance_derivative" in data, "Key 'variance_derivative' missing from results.json."
    assert "kl_divergence" in data, "Key 'kl_divergence' missing from results.json."

    assert math.isclose(data["c_star"], expected_c_star, abs_tol=1e-4), \
        f"'c_star' {data['c_star']} is not within 1e-4 of expected {expected_c_star}."

    assert math.isclose(data["variance_derivative"], expected_v_prime, abs_tol=1e-4), \
        f"'variance_derivative' {data['variance_derivative']} is not within 1e-4 of expected {expected_v_prime}."

    assert math.isclose(data["kl_divergence"], expected_kl, abs_tol=1e-4), \
        f"'kl_divergence' {data['kl_divergence']} is not within 1e-4 of expected {expected_kl}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
