#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest
import numpy as np
from scipy.optimize import minimize

def rosenbrock(v):
    x, y = v[0], v[1]
    return (1 - x)**2 + 100 * (y - x**2)**2

def get_truth():
    np.random.seed(123)
    starts = np.random.normal(0.0, 2.0, (100, 2))

    bfgs_success = 0
    nm_success = 0

    for pt in starts:
        res_bfgs = minimize(rosenbrock, pt, method='BFGS')
        if np.linalg.norm(res_bfgs.x - np.array([1.0, 1.0])) < 1e-3:
            bfgs_success += 1

        res_nm = minimize(rosenbrock, pt, method='Nelder-Mead')
        if np.linalg.norm(res_nm.x - np.array([1.0, 1.0])) < 1e-3:
            nm_success += 1

    return {
        "bfgs_convergence_rate": bfgs_success / 100.0,
        "nm_convergence_rate": nm_success / 100.0
    }

def test_convergence_results():
    result_path = "/home/user/convergence_results.json"
    assert os.path.exists(result_path), f"File {result_path} does not exist. The script may not have run or saved the output correctly."

    with open(result_path, 'r') as f:
        try:
            agent_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {result_path} is not valid JSON.")

    assert "bfgs_convergence_rate" in agent_data, "Missing 'bfgs_convergence_rate' in JSON output."
    assert "nm_convergence_rate" in agent_data, "Missing 'nm_convergence_rate' in JSON output."

    truth_data = get_truth()

    assert abs(agent_data["bfgs_convergence_rate"] - truth_data["bfgs_convergence_rate"]) < 1e-6, \
        f"Incorrect BFGS convergence rate. Expected {truth_data['bfgs_convergence_rate']}, got {agent_data['bfgs_convergence_rate']}."

    assert abs(agent_data["nm_convergence_rate"] - truth_data["nm_convergence_rate"]) < 1e-6, \
        f"Incorrect Nelder-Mead convergence rate. Expected {truth_data['nm_convergence_rate']}, got {agent_data['nm_convergence_rate']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
