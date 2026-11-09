#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import struct
import math
import pytest

def compute_expected_values():
    data_path = "/home/user/data/observations.dat"
    if not os.path.exists(data_path):
        pytest.fail(f"Data file missing at {data_path}")

    with open(data_path, 'rb') as f:
        data = f.read()

    n_particles = 10
    n_steps = 100
    expected_size = n_particles * n_steps * 8
    if len(data) != expected_size:
        pytest.fail(f"Data file size is {len(data)}, expected {expected_size}")

    obs_data = struct.unpack(f'{n_particles * n_steps}d', data)

    best_p0 = 0.0
    best_p1 = 0.0
    best_mse = float('inf')

    grid_size = 50
    p_vals = [i * (5.0 / (grid_size - 1)) for i in range(grid_size)]

    for p0 in p_vals:
        for p1 in p_vals:
            mse = 0.0
            for p in range(n_particles):
                y = 5.0
                for t in range(n_steps):
                    obs = obs_data[p * n_steps + t]
                    diff = obs - y
                    mse += diff * diff

                    for s in range(10):
                        y += 0.01 * (-p0 * y + p1 * math.sin(y))

            if mse < best_mse:
                best_mse = mse
                best_p0 = p0
                best_p1 = p1

    residuals = []
    for p in range(n_particles):
        y = 5.0
        for t in range(n_steps):
            obs = obs_data[p * n_steps + t]
            residuals.append(obs - y)
            for s in range(10):
                y += 0.01 * (-best_p0 * y + best_p1 * math.sin(y))

    mean = sum(residuals) / len(residuals)
    var = sum((r - mean)**2 for r in residuals) / len(residuals)
    stddev = math.sqrt(var)

    return best_p0, best_p1, stddev

def test_solution_file_exists():
    solution_path = "/home/user/solution.txt"
    assert os.path.exists(solution_path), f"Solution file is missing at {solution_path}"
    assert os.path.isfile(solution_path), f"Path {solution_path} is not a file"

def test_solution_correctness():
    solution_path = "/home/user/solution.txt"
    assert os.path.exists(solution_path), "Solution file not found."

    with open(solution_path, 'r') as f:
        content = f.read().strip()

    assert content, "Solution file is empty."

    parts = [p.strip() for p in content.split(',')]
    assert len(parts) == 3, f"Expected 3 comma-separated values, got {len(parts)} in '{content}'"

    try:
        user_p0 = float(parts[0])
        user_p1 = float(parts[1])
        user_stddev = float(parts[2])
    except ValueError:
        pytest.fail("Could not parse values as floats. Ensure they are comma-separated numbers.")

    expected_p0, expected_p1, expected_stddev = compute_expected_values()

    assert math.isclose(user_p0, expected_p0, abs_tol=1e-3), \
        f"p0 value incorrect. Expected ~{expected_p0:.4f}, got {user_p0}"
    assert math.isclose(user_p1, expected_p1, abs_tol=1e-3), \
        f"p1 value incorrect. Expected ~{expected_p1:.4f}, got {user_p1}"
    assert math.isclose(user_stddev, expected_stddev, abs_tol=1e-3), \
        f"residual_stddev value incorrect. Expected ~{expected_stddev:.4f}, got {user_stddev}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
