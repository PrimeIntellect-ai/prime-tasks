#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import math

def compute_expected_error(N):
    """
    Computes the expected maximum absolute error for the 1D nonlinear ODE
    using a pure Python implementation of the Newton-Raphson method and
    Thomas algorithm for the tridiagonal system.
    """
    h = 1.0 / N
    x = [i * h for i in range(N + 1)]
    u_exact = [math.exp(xi) for xi in x]

    # Initial guess for interior points
    U = [1.0] * (N - 1)

    for _ in range(50):
        R = [0.0] * (N - 1)
        A = [0.0] * (N - 1)  # subdiagonal
        B = [0.0] * (N - 1)  # diagonal
        C = [0.0] * (N - 1)  # superdiagonal

        for i in range(N - 1):
            xi = x[i + 1]
            ui = U[i]
            ui_minus_1 = U[i - 1] if i > 0 else 1.0
            ui_plus_1 = U[i + 1] if i < N - 2 else math.exp(1.0)

            # Residual
            R[i] = (ui_minus_1 - 2*ui + ui_plus_1) / (h**2) - ui**2 - (math.exp(xi) - math.exp(2*xi))

            # Jacobian entries
            B[i] = -2.0 / (h**2) - 2*ui
            if i > 0:
                A[i] = 1.0 / (h**2)
            if i < N - 2:
                C[i] = 1.0 / (h**2)

        # Thomas algorithm
        c_prime = [0.0] * (N - 1)
        d_prime = [0.0] * (N - 1)

        c_prime[0] = C[0] / B[0]
        d_prime[0] = -R[0] / B[0]

        for i in range(1, N - 1):
            m = 1.0 / (B[i] - A[i] * c_prime[i - 1])
            c_prime[i] = C[i] * m
            d_prime[i] = (-R[i] - A[i] * d_prime[i - 1]) * m

        delta = [0.0] * (N - 1)
        delta[-1] = d_prime[-1]
        for i in range(N - 3, -1, -1):
            delta[i] = d_prime[i] - c_prime[i] * delta[i + 1]

        max_delta = 0.0
        for i in range(N - 1):
            U[i] += delta[i]
            max_delta = max(max_delta, abs(delta[i]))

        if max_delta < 1e-12:
            break

    max_err = 0.0
    for i in range(N - 1):
        max_err = max(max_err, abs(U[i] - u_exact[i + 1]))

    return max_err

def test_convergence_log_exists_and_correct():
    log_file = "/home/user/convergence.log"
    assert os.path.exists(log_file), f"Log file {log_file} does not exist."
    assert os.path.isfile(log_file), f"{log_file} is not a file."

    expected_Ns = [10, 20, 40, 80]
    parsed_data = {}

    with open(log_file, "r") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["N", "MaxError"], f"Header in {log_file} is incorrect. Expected ['N', 'MaxError'], got {header}"

        for row in reader:
            assert len(row) == 2, f"Invalid row format in {log_file}: {row}"
            try:
                n_val = int(row[0])
                err_val = float(row[1])
                parsed_data[n_val] = err_val
            except ValueError:
                assert False, f"Could not parse numeric values from row: {row}"

    for n_val in expected_Ns:
        assert n_val in parsed_data, f"Missing results for N={n_val} in {log_file}"

        expected_err = compute_expected_error(n_val)
        actual_err = parsed_data[n_val]

        # Check within 2% tolerance
        rel_diff = abs(actual_err - expected_err) / expected_err
        assert rel_diff <= 0.02, (
            f"Error value for N={n_val} is out of tolerance. "
            f"Expected ~{expected_err:e}, got {actual_err:e}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
