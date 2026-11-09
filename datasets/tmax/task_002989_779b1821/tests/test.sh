#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import csv
import numpy as np
import pytest


def exact_C(x):
    D = 0.01
    k = 0.1
    sqrt_kd = math.sqrt(k / D)
    return math.sinh(sqrt_kd * (1 - x)) / math.sinh(sqrt_kd)


def solve_fd(N):
    D = 0.01
    k = 0.1
    dx = 1.0 / (N - 1)
    factor = D / (dx * dx)

    a = [factor] * N
    b_diag = [-2 * factor - k] * N
    c = [factor] * N
    d = [0.0] * N

    b_diag[0] = 1.0
    c[0] = 0.0
    d[0] = 1.0

    a[-1] = 0.0
    b_diag[-1] = 1.0
    d[-1] = 0.0

    c_prime = [0.0] * N
    d_prime = [0.0] * N

    c_prime[0] = c[0] / b_diag[0]
    d_prime[0] = d[0] / b_diag[0]

    for i in range(1, N):
        m = 1.0 / (b_diag[i] - a[i] * c_prime[i - 1])
        c_prime[i] = c[i] * m
        d_prime[i] = (d[i] - a[i] * d_prime[i - 1]) * m

    C_num = [0.0] * N
    C_num[-1] = d_prime[-1]
    for i in range(N - 2, -1, -1):
        C_num[i] = d_prime[i] - c_prime[i] * C_num[i + 1]

    max_err = 0.0
    for i in range(N):
        x = i * dx
        err = abs(C_num[i] - exact_C(x))
        if err > max_err:
            max_err = err

    return max_err


def compute_expected_phase1():
    N = 5
    while True:
        err = solve_fd(N)
        if err < 1e-3:
            break
        N = 2 * (N - 1) + 1
    return N, err


def compute_expected_bootstrap_ci():
    csv_path = '/home/user/protein_counts.csv'
    if not os.path.exists(csv_path):
        return {}

    columns = ["x_0.2", "x_0.4", "x_0.6", "x_0.8"]
    with open(csv_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        if reader.fieldnames is None or any(col not in reader.fieldnames for col in columns):
            return {}
        data = {col: [] for col in columns}
        for row in reader:
            for col in columns:
                data[col].append(float(row[col]))

    # Reproduce the required seeded procedure: seed once, then draw exactly
    # 10,000 bootstrap samples for each column in report order.
    np.random.seed(42)
    expected = {}
    for col in columns:
        values = np.asarray(data[col], dtype=float)
        samples = np.random.choice(values, size=(10000, len(values)), replace=True)
        bootstrap_means = samples.mean(axis=1)
        expected[col] = tuple(np.percentile(bootstrap_means, [2.5, 97.5]))

    return expected


@pytest.fixture
def report_data():
    report_path = '/home/user/analysis_report.json'
    assert os.path.exists(report_path), f"File {report_path} does not exist."
    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")
    return data


def test_analytical_validation(report_data):
    assert "analytical_validation" in report_data, "Missing 'analytical_validation' key in report."
    av = report_data["analytical_validation"]
    assert "final_N" in av, "Missing 'final_N' in analytical_validation."
    assert "max_error" in av, "Missing 'max_error' in analytical_validation."

    expected_N, expected_err = compute_expected_phase1()

    assert av["final_N"] == expected_N, f"Expected final_N to be {expected_N}, got {av['final_N']}."
    assert math.isclose(av["max_error"], expected_err, rel_tol=1e-3), \
        f"Expected max_error close to {expected_err}, got {av['max_error']}."


def test_bootstrap_ci(report_data):
    assert "bootstrap_95_ci" in report_data, "Missing 'bootstrap_95_ci' key in report."
    ci_data = report_data["bootstrap_95_ci"]

    expected_cis = compute_expected_bootstrap_ci()
    assert expected_cis, "Could not read data from /home/user/protein_counts.csv to verify CIs."

    for col in ["x_0.2", "x_0.4", "x_0.6", "x_0.8"]:
        assert col in ci_data, f"Missing {col} in bootstrap_95_ci."
        bounds = ci_data[col]
        assert isinstance(bounds, list) and len(bounds) == 2, f"Expected a list of 2 floats for {col}."

        lower, upper = bounds
        expected_lower, expected_upper = expected_cis[col]

        assert math.isclose(lower, expected_lower, rel_tol=1e-9, abs_tol=1e-9), \
            f"Lower bound for {col} ({lower}) does not match the seeded 10,000-resample bootstrap result ({expected_lower})."
        assert math.isclose(upper, expected_upper, rel_tol=1e-9, abs_tol=1e-9), \
            f"Upper bound for {col} ({upper}) does not match the seeded 10,000-resample bootstrap result ({expected_upper})."
        assert lower < upper, f"Lower bound must be less than upper bound for {col}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
