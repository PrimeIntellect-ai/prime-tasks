#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest
import numpy as np
from scipy.optimize import root


def expected_results():
    """Independently solve the instructed system from the required initial guess."""
    def equations(values):
        x, y = values
        return [
            2 * x - y + np.exp(-x) - 1,
            -x + 2 * y + np.sin(y) - 2,
        ]

    solution = root(equations, [0.0, 0.0])
    assert solution.success, f"Verifier could not solve the instructed system: {solution.message}"

    x, y = solution.x
    jacobian = np.array([
        [2 - np.exp(-x), -1],
        [-1, 2 + np.cos(y)],
    ])
    return float(x), float(y), float(np.linalg.cond(jacobian))


def test_output_file_exists_and_valid():
    """Check that the output JSON file exists and is valid."""
    output_file = "/home/user/model_fit_results.json"
    assert os.path.exists(output_file), f"Output file {output_file} is missing. Did you save the results?"
    assert os.path.isfile(output_file), f"{output_file} is not a file."

    with open(output_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_file} does not contain valid JSON.")

    assert isinstance(data, dict), "The JSON file must contain a dictionary/object."


def test_output_values():
    """Check that the output JSON contains the correct keys and values."""
    output_file = "/home/user/model_fit_results.json"
    if not os.path.exists(output_file):
        pytest.fail(f"Output file {output_file} is missing.")

    with open(output_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_file} does not contain valid JSON.")

    expected_keys = {"x", "y", "condition_number"}
    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"The JSON file is missing the following keys: {missing_keys}"

    # Derive the expected root from the specified initial guess and evaluate
    # the instructed analytical Jacobian at that root.
    expected_x, expected_y, expected_cond = expected_results()

    x_val = data["x"]
    y_val = data["y"]
    cond_val = data["condition_number"]

    assert isinstance(x_val, (int, float)), "The value for 'x' must be a number."
    assert isinstance(y_val, (int, float)), "The value for 'y' must be a number."
    assert isinstance(cond_val, (int, float)), "The value for 'condition_number' must be a number."

    assert math.isclose(x_val, expected_x, abs_tol=1e-5), \
        f"Value of 'x' ({x_val}) is not within 1e-5 of the expected value ({expected_x})."

    assert math.isclose(y_val, expected_y, abs_tol=1e-5), \
        f"Value of 'y' ({y_val}) is not within 1e-5 of the expected value ({expected_y})."

    assert math.isclose(cond_val, expected_cond, abs_tol=1e-4), \
        f"Value of 'condition_number' ({cond_val}) is not within 1e-4 of the expected value ({expected_cond})."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
