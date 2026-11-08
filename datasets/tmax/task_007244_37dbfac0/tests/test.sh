#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import sys
import subprocess

import numpy as np
import pytest
from scipy.optimize import minimize


def reference_solution(seq):
    features = np.array([
        seq.count('A') * 20.0,
        seq.count('C') * 20.0,
        seq.count('G') * 20.0,
    ])

    def objective(w):
        terms = w * features
        m = np.max(terms)
        lse = m + np.log(np.sum(np.exp(terms - m)))
        penalty = (w[0] - 2) ** 2 + (w[1] - 3) ** 2 + (w[2] + 1) ** 2
        return float(lse + penalty)

    def gradient(w):
        terms = w * features
        m = np.max(terms)
        exps = np.exp(terms - m)
        probabilities = exps / np.sum(exps)
        return features * probabilities + 2.0 * (w - np.array([2.0, 3.0, -1.0]))

    result = minimize(
        objective,
        np.array([0.0, 0.0, 0.0]),
        jac=gradient,
        method="L-BFGS-B",
        options={"ftol": 1e-14, "gtol": 1e-10, "maxiter": 10000},
    )
    assert result.success, f"Reference optimization failed: {result.message}"
    return result.x, objective(result.x)


def test_result_json():
    solve_path = "/home/user/solve.py"
    assert os.path.isfile(solve_path), f"File {solve_path} does not exist."

    result_path = "/home/user/result.json"
    if os.path.exists(result_path):
        os.remove(result_path)

    completed = subprocess.run(
        [sys.executable, solve_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert completed.returncode == 0, (
        f"solve.py exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(result_path), f"File {result_path} does not exist."

    with open(result_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {result_path} is not valid JSON.")

    assert "sequence" in data, "'sequence' key missing in result.json"
    assert "optimal_weights" in data, "'optimal_weights' key missing in result.json"
    assert "min_energy" in data, "'min_energy' key missing in result.json"

    # 1. Check assembled sequence
    assert data["sequence"] == "ACCAAAT", f"Expected sequence 'ACCAAAT', got '{data['sequence']}'"

    # 2. Check optimal weights against an independently computed optimum.
    weights = data["optimal_weights"]
    assert isinstance(weights, list) and len(weights) == 3, "optimal_weights must be a list of 3 floats"

    expected_weights, expected_energy = reference_solution("ACCAAAT")
    for w, ew in zip(weights, expected_weights):
        assert isinstance(w, (int, float)), "Weights must be numeric"
        assert math.isclose(w, float(ew), rel_tol=1e-2, abs_tol=1e-2), f"Weight {w} is not close to expected {ew}"

    # 3. Check minimum energy
    energy = data["min_energy"]
    assert isinstance(energy, (int, float)), "min_energy must be numeric"
    assert math.isclose(energy, expected_energy, rel_tol=1e-2, abs_tol=1e-2), (
        f"min_energy {energy} is not close to expected {expected_energy}"
    )


def test_energy_function_stability():
    energy_path = "/home/user/energy.py"
    assert os.path.isfile(energy_path), f"File {energy_path} does not exist."

    sys.modules.pop("energy", None)
    sys.path.insert(0, "/home/user")
    try:
        from energy import compute_energy
    except ImportError:
        pytest.fail("Could not import compute_energy from /home/user/energy.py")
    finally:
        sys.path.pop(0)

    try:
        val = compute_energy([1000.0, 1000.0, 1000.0], "ACG")
    except OverflowError:
        pytest.fail("compute_energy raised OverflowError, indicating it is still numerically unstable.")
    except Exception as e:
        pytest.fail(f"compute_energy raised an unexpected error: {e}")

    assert not math.isinf(val), "compute_energy returned inf, indicating it is still numerically unstable."
    assert not math.isnan(val), "compute_energy returned NaN, indicating it is still numerically unstable."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
