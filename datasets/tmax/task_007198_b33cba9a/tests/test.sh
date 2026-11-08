#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import numpy as np
import matplotlib.image as mpimg


def test_generate_data_script_exists():
    assert os.path.isfile("/home/user/generate_data.py"), "The script /home/user/generate_data.py does not exist."


def test_solution_plot_exists_and_is_valid():
    plot_path = "/home/user/solution.png"
    assert os.path.isfile(plot_path), "The plot /home/user/solution.png does not exist."
    assert os.path.getsize(plot_path) > 0, "The plot is empty."
    with open(plot_path, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "solution.png is not a PNG file."
    image = mpimg.imread(plot_path)
    assert image.ndim in (2, 3) and image.shape[0] > 1 and image.shape[1] > 1, "solution.png is not a valid non-empty image."


def test_converged_data_csv():
    csv_path = "/home/user/converged_data.csv"
    assert os.path.exists(csv_path), f"The CSV file {csv_path} does not exist."

    with open(csv_path, "r", encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))

    assert len(rows) == 42, f"Expected 42 lines in the CSV (1 header + 41 data rows), but got {len(rows)}."

    headers = [h.strip() for h in rows[0]]
    expected_headers = ["x", "u_num", "u_exact", "error"]
    assert headers == expected_headers, f"Expected headers {expected_headers}, but got {headers}."

    xs = []
    u_nums = []
    max_error = 0.0
    midpoint_found = False

    for row in rows[1:]:
        assert len(row) == 4, f"Row {row} does not have exactly 4 columns."
        try:
            x = float(row[0])
            u_num = float(row[1])
            u_exact = float(row[2])
            error = float(row[3])
        except ValueError:
            assert False, f"Could not parse row values as floats: {row}"

        assert all(math.isfinite(v) for v in (x, u_num, u_exact, error)), f"Row contains a non-finite value: {row}"

        expected_error = abs(u_num - u_exact)
        assert math.isclose(error, expected_error, rel_tol=1e-5, abs_tol=1e-8), f"Error column {error} does not match abs(u_num - u_exact) {expected_error} at x={x}."

        if error > max_error:
            max_error = error

        expected_u_exact = math.sin(math.pi * x)
        assert math.isclose(u_exact, expected_u_exact, rel_tol=1e-5, abs_tol=1e-8), f"u_exact {u_exact} does not match expected {expected_u_exact} at x={x}."

        if math.isclose(x, 0.5, rel_tol=1e-5, abs_tol=1e-5):
            midpoint_found = True
            assert math.isclose(u_exact, 1.0, rel_tol=1e-5, abs_tol=1e-5), f"Expected u_exact at x=0.5 to be 1.0, got {u_exact}."
            assert math.isclose(u_num, 1.000514, rel_tol=1e-3, abs_tol=1e-3), f"Expected u_num at x=0.5 to be approx 1.000514, got {u_num}."

        xs.append(x)
        u_nums.append(u_num)

    # Convergence from N=10 by doubling first occurs at N=40, so the output
    # must be the complete, ordered N=40 mesh including both boundaries.
    expected_xs = np.linspace(0.0, 1.0, 41)
    assert np.allclose(xs, expected_xs, rtol=0.0, atol=1e-12), "x-values are not the complete ordered N=40 grid from 0 to 1."
    assert len(set(xs)) == 41, "The x-values must be distinct."

    u = np.asarray(u_nums, dtype=float)
    assert math.isclose(u[0], 0.0, rel_tol=0.0, abs_tol=1e-8), "u_num does not satisfy u(0)=0."
    assert math.isclose(u[-1], 0.0, rel_tol=0.0, abs_tol=1e-8), "u_num does not satisfy u(1)=0."

    # Independently construct and solve the required central-difference system.
    n = 40
    h = 1.0 / n
    interior_x = expected_xs[1:-1]
    A = np.diag(-2.0 * np.ones(n - 1))
    A += np.diag(np.ones(n - 2), 1)
    A += np.diag(np.ones(n - 2), -1)
    rhs = -(h * h) * (math.pi ** 2) * np.sin(math.pi * interior_x)
    expected_interior = np.linalg.solve(A, rhs)

    residual = A @ u[1:-1] - rhs
    assert np.max(np.abs(residual)) < 4e-5, "u_num does not satisfy the second-order finite-difference equations."
    assert np.allclose(u[1:-1], expected_interior, rtol=0.0, atol=1e-5), "u_num is not the N=40 central finite-difference solution."

    assert midpoint_found, "Midpoint x=0.5 was not found in the CSV data."
    assert max_error < 1.0e-3, f"Maximum error {max_error} is not strictly less than 1.0e-3."
    assert max_error > 0.0, "Maximum error should be greater than 0 (numerical solution should not be perfectly exact)."
TEST_EOF

# Remove prior products so the submitted script must successfully regenerate them.
rm -f /home/user/converged_data.csv /home/user/solution.png
run_ok=1
if ! timeout 180s bash -c 'cd /home/user && python3 /home/user/generate_data.py'; then
    run_ok=0
fi

if [ "$run_ok" -eq 1 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
