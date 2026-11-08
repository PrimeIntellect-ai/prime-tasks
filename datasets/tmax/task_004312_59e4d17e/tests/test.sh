#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess

import pytest

SOURCE_PATH = "/home/user/thermal_sim.c"
EXECUTABLE_PATH = "/tmp/thermal_sim_submission"
RESULTS_PATH = "/home/user/results.json"
SENSOR_PATH = "/home/user/sensor_data.txt"

CANONICAL_SENSOR = [
    25.0, 33.1, 48.2, 71.4, 115.6, 142.3,
    115.6, 71.4, 48.2, 33.1, 25.0,
]


def run_sim(dt):
    dx = 0.1
    alpha = 0.01
    n = 11
    u = [25.0] * n
    power = [0.0] * n
    power[4] = power[5] = power[6] = 1000.0

    steps = int(round(2.0 / dt))
    for _ in range(steps):
        u_new = list(u)
        for i in range(1, n - 1):
            d2u = (u[i - 1] - 2.0 * u[i] + u[i + 1]) / (dx ** 2)
            u_new[i] = u[i] + dt * (alpha * d2u + power[i])
        u = u_new
    return u


def converged_solution():
    dt = 0.1
    prev_center = -1000.0
    while True:
        u = run_sim(dt)
        center = u[5]
        if dt != 0.1 and abs(center - prev_center) < 0.01:
            return dt, u
        prev_center = center
        dt /= 2.0


OPTIMAL_DT, FINAL_U = converged_solution()


def compute_expected_results(sensor):
    errors = [FINAL_U[i] - sensor[i] for i in range(11)]
    mean = sum(errors) / 11.0
    variance = sum((error - mean) ** 2 for error in errors) / 11.0
    return {
        "optimal_dt": OPTIMAL_DT,
        "center_temp": FINAL_U[5],
        "error_mean": mean,
        "error_variance": variance,
    }


def write_sensor_data(sensor):
    with open(SENSOR_PATH, "w") as handle:
        for value in sensor:
            handle.write(f"{value:.10f}\n")


def execute_submission(sensor):
    write_sensor_data(sensor)
    if os.path.lexists(RESULTS_PATH):
        os.remove(RESULTS_PATH)

    completed = subprocess.run(
        [EXECUTABLE_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        "Compiled simulator exited unsuccessfully.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
    assert os.path.exists(RESULTS_PATH), f"Results file not found at {RESULTS_PATH} after running the simulator"

    with open(RESULTS_PATH, "r") as handle:
        try:
            return json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} is not valid JSON.")


def assert_results(results, expected):
    keys = ["optimal_dt", "center_temp", "error_mean", "error_variance"]
    for key in keys:
        assert key in results, f"Missing key '{key}' in {RESULTS_PATH}"
        actual_val = results[key]
        expected_val = expected[key]
        assert isinstance(actual_val, (int, float)), f"Value for '{key}' must be a number."
        assert abs(actual_val - expected_val) < 1e-3, (
            f"Mismatch in '{key}': expected approx {expected_val:.4f}, got {actual_val:.4f}"
        )


def test_compiled_simulator_and_results():
    assert os.path.isfile(SOURCE_PATH), f"C source file not found at {SOURCE_PATH}"
    assert os.path.getsize(SOURCE_PATH) > 0, f"C source file is empty at {SOURCE_PATH}"
    assert os.path.isfile(EXECUTABLE_PATH), "The submitted C source was not compiled into an executable"
    assert os.access(EXECUTABLE_PATH, os.X_OK), "The compiled simulator is not executable"

    try:
        # Preserve the original fixed-dataset assertions.
        results = execute_submission(CANONICAL_SENSOR)
        assert_results(results, compute_expected_results(CANONICAL_SENSOR))

        # Exercise the compiled artifact with verifier-generated sensor inputs so
        # a precomputed results.json cannot satisfy the task.
        rng = random.SystemRandom()
        for _ in range(3):
            sensor = [rng.uniform(20.0, 160.0) for _ in range(11)]
            results = execute_submission(sensor)
            assert_results(results, compute_expected_results(sensor))
    finally:
        write_sensor_data(CANONICAL_SENSOR)
TEST_EOF

if [[ -f /home/user/thermal_sim.c ]] \
   && [[ -s /home/user/thermal_sim.c ]] \
   && gcc -std=c11 -O2 -Wall -Wextra /home/user/thermal_sim.c -lm -o /tmp/thermal_sim_submission \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
