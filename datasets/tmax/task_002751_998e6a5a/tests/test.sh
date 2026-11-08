#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import numpy as np
from scipy.integrate import solve_ivp


def compute_expected_values():
    m = 1.0
    c = 0.1
    k = 1.0
    alpha = 0.5
    t = np.linspace(0.0, 10.0, 1000)
    position_rows = []
    max_abs_jerk = 0.0

    def system(_, state):
        x, v = state
        a = -(c * v + k * x + alpha * x**3) / m
        return [v, a]

    for x0 in np.linspace(-2.0, 2.0, 10):
        for v0 in np.linspace(-2.0, 2.0, 5):
            solution = solve_ivp(
                system,
                (0.0, 10.0),
                [x0, v0],
                t_eval=t,
                rtol=1e-6,
                atol=1e-8,
            )
            assert solution.success, solution.message
            x = solution.y[0]
            v = solution.y[1]
            acceleration = -(c * v + k * x + alpha * x**3) / m
            jerk = np.gradient(acceleration, t)
            max_abs_jerk = max(max_abs_jerk, float(np.max(np.abs(jerk))))
            position_rows.append(x)

    matrix = np.asarray(position_rows)
    singular_values = np.linalg.svd(matrix, compute_uv=False)
    return [float(value) for value in singular_values[:3]], max_abs_jerk


def test_ml_data_summary_exists_and_correct():
    file_path = "/home/user/ml_data_summary.json"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {file_path} is not valid JSON."

    assert "top_3_singular_values" in data, "The JSON file is missing the 'top_3_singular_values' key."
    assert "max_abs_jerk" in data, "The JSON file is missing the 'max_abs_jerk' key."

    top_3 = data["top_3_singular_values"]
    max_jerk = data["max_abs_jerk"]

    assert isinstance(top_3, list), "'top_3_singular_values' should be a list."
    assert len(top_3) == 3, "'top_3_singular_values' must contain exactly 3 values."
    assert isinstance(max_jerk, (int, float)), "'max_abs_jerk' should be a number."
    assert all(isinstance(value, (int, float)) for value in top_3), "All singular values should be numbers."
    assert all(math.isfinite(value) for value in top_3), "All singular values should be finite."
    assert math.isfinite(max_jerk), "'max_abs_jerk' should be finite."

    expected_top_3, expected_max_jerk = compute_expected_values()

    # Check top 3 singular values with the original relative tolerance.
    for i, (val, exp) in enumerate(zip(top_3, expected_top_3)):
        assert math.isclose(val, exp, rel_tol=5e-3), (
            f"Singular value at index {i} ({val}) is not close to the expected value ({exp})."
        )

    # Check max absolute jerk with the original relative tolerance.
    assert math.isclose(max_jerk, expected_max_jerk, rel_tol=5e-3), (
        f"Max absolute jerk ({max_jerk}) is not close to the expected value ({expected_max_jerk})."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
