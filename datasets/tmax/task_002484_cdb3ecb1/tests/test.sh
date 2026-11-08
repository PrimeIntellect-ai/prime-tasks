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
from astropy.io import fits


def test_solution_file_exists():
    """Check if the solution.json file exists."""
    file_path = "/home/user/solution.json"
    assert os.path.isfile(file_path), f"File {file_path} does not exist. The Go program may not have run or failed to output."


def test_solution_contents_match():
    """Check if the solution matches the expected ground truth within tolerance."""
    solution_path = "/home/user/solution.json"
    matrix_path = "/home/user/data/matrix.fits"

    assert os.path.isfile(matrix_path), f"Input FITS file {matrix_path} is missing."
    assert os.path.isfile(solution_path), f"Solution file {solution_path} is missing."

    with open(solution_path, "r") as f:
        try:
            agent_ans = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {solution_path} is not valid JSON.")

    with fits.open(matrix_path) as hdul:
        matrix = np.asarray(hdul[0].data, dtype=np.float64)
    expected = np.linalg.solve(
        matrix + 0.05 * np.eye(matrix.shape[0], dtype=np.float64),
        np.ones(matrix.shape[0], dtype=np.float64),
    ).tolist()

    assert isinstance(agent_ans, list), f"Expected a JSON array in {solution_path}, got {type(agent_ans).__name__}."
    assert len(agent_ans) == len(expected), f"Expected {len(expected)} elements, got {len(agent_ans)}."

    for i, (a, t) in enumerate(zip(agent_ans, expected)):
        assert isinstance(a, (int, float)), f"Element at index {i} is not a number: {a}"
        assert math.isclose(a, t, rel_tol=1e-4, abs_tol=1e-4), f"Value at index {i} does not match. Expected {t}, got {a}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
