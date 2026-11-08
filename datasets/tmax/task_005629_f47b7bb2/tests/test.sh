#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import sys
import importlib.util

def compute_heat_expected(N):
    dx = 1.0 / N
    dy = 1.0 / N
    vals = []
    for x in range(N):
        for y in range(N):
            val = math.sin((x + 0.5) * dx) * math.cos((y + 0.5) * dy) * 0.01
            vals.append(val)
    return math.fsum(vals)

def test_heat_sim_fixed():
    path = "/home/user/heat_sim.py"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, 'r') as f:
        content = f.read()
    assert "math.fsum" in content, "The compute_heat function must use math.fsum."

    # Dynamically load the module
    spec = importlib.util.spec_from_file_location("heat_sim", path)
    heat_sim = importlib.util.module_from_spec(spec)
    sys.modules["heat_sim"] = heat_sim
    spec.loader.exec_module(heat_sim)

    # Test if the function is independent of num_chunks and matches the exact fsum
    expected_10 = compute_heat_expected(10)
    result_1 = heat_sim.compute_heat(10, num_chunks=1)
    result_2 = heat_sim.compute_heat(10, num_chunks=4)
    result_3 = heat_sim.compute_heat(10, num_chunks=10)

    assert result_1 == expected_10, f"compute_heat(10) returned {result_1}, expected {expected_10}"
    assert result_2 == expected_10, "compute_heat result varies with num_chunks."
    assert result_3 == expected_10, "compute_heat result varies with num_chunks."

def test_final_report():
    report_path = "/home/user/final_report.json"
    assert os.path.isfile(report_path), f"File {report_path} is missing."

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{report_path} is not a valid JSON file.")

    assert "converged_N" in report, "Missing 'converged_N' in final_report.json"
    assert "converged_value" in report, "Missing 'converged_value' in final_report.json"
    assert "obs_value" in report, "Missing 'obs_value' in final_report.json"

    # Calculate expected converged N and value
    prev = compute_heat_expected(10)
    expected_converged_N = None
    expected_converged_value = None

    for N in [20, 40, 80, 160, 320]:
        curr = compute_heat_expected(N)
        if abs(curr - prev) < 1e-6:
            expected_converged_N = N
            expected_converged_value = curr
            break
        prev = curr

    assert expected_converged_N is not None, "Failed to find expected converged N."

    assert report["converged_N"] == expected_converged_N, f"Expected converged_N to be {expected_converged_N}, got {report['converged_N']}"
    assert math.isclose(report["converged_value"], expected_converged_value, rel_tol=1e-12), f"Expected converged_value to be {expected_converged_value}, got {report['converged_value']}"

    # Calculate expected obs_value
    obs_path = "/home/user/obs_data.txt"
    assert os.path.isfile(obs_path), f"File {obs_path} is missing."
    with open(obs_path, 'r') as f:
        obs_vals = [float(x) for x in f.read().split(',')]
    expected_obs_value = math.fsum(obs_vals)

    assert math.isclose(report["obs_value"], expected_obs_value, rel_tol=1e-12), f"Expected obs_value to be {expected_obs_value}, got {report['obs_value']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
