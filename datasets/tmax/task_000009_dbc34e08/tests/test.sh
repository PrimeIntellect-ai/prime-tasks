#!/bin/bash
mkdir -p /logs/verifier
rm -f /tmp/test_final_state.py

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import json
import math
import subprocess


def test_simulate_script_executes_and_generates_results():
    """Test that the required simulation artifact exists and generates fresh results."""
    script_path = "/home/user/simulate.py"
    json_path = "/home/user/results.json"

    assert os.path.isfile(script_path), f"File {script_path} does not exist or is not a regular file."
    assert not os.path.islink(script_path), f"File {script_path} must not be a symbolic link."

    try:
        os.remove(json_path)
    except FileNotFoundError:
        pass

    completed = subprocess.run(
        [sys.executable, script_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"{script_path} failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(json_path), f"Executing {script_path} did not create {json_path}."


def test_observed_data_csv():
    """Test that the observed_data.csv is correctly formatted and contains the right data."""
    csv_path = "/home/user/observed_data.csv"
    assert os.path.exists(csv_path), f"File {csv_path} does not exist."

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 6, f"Expected 6 lines in {csv_path}, found {len(lines)}"
    assert lines[0] == "time,count", f"Expected header 'time,count', found '{lines[0]}'"

    expected_data = [
        "0.0,100.0",
        "0.5,10.2",
        "1.0,2.7",
        "1.5,2.1",
        "2.0,2.0"
    ]

    for i, expected_line in enumerate(expected_data):
        assert lines[i+1] == expected_line, f"Line {i+2} mismatch: expected '{expected_line}', found '{lines[i+1]}'"


def test_results_json():
    """Test that results.json has the correct computed values."""
    json_path = "/home/user/results.json"
    assert os.path.exists(json_path), f"File {json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} is not a valid JSON file."

    expected_keys = {"analytical_t_1", "numerical_t_1", "max_stable_dt"}
    assert set(results.keys()) == expected_keys, f"JSON keys mismatch. Expected {expected_keys}, found {set(results.keys())}"

    # Compute expected values
    alpha = 10.0
    beta = 5.0
    c0 = 100.0
    t = 1.0

    expected_analytical = (alpha / beta) + (c0 - (alpha / beta)) * math.exp(-beta * t)

    # Numerical Euler
    dt = 0.1
    c = c0
    steps = int(round(t / dt))
    for _ in range(steps):
        c = c + dt * (alpha - beta * c)
    expected_numerical = c

    expected_max_dt = 2.0 / beta

    assert abs(results["analytical_t_1"] - expected_analytical) < 1e-4, \
        f"analytical_t_1 mismatch. Expected ~{expected_analytical:.5f}, got {results['analytical_t_1']}"

    assert abs(results["numerical_t_1"] - expected_numerical) < 1e-4, \
        f"numerical_t_1 mismatch. Expected ~{expected_numerical:.5f}, got {results['numerical_t_1']}"

    assert abs(results["max_stable_dt"] - expected_max_dt) < 1e-4, \
        f"max_stable_dt mismatch. Expected ~{expected_max_dt:.5f}, got {results['max_stable_dt']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
