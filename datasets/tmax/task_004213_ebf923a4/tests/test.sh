#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import pytest

def get_expected_data():
    def f(t, x):
        return -x**3 + math.cos(t)

    x = 0.5
    t = 0.0
    dt = 0.01

    expected_trajectory = []
    expected_trajectory.append((t, x))

    for _ in range(500):
        k1 = f(t, x)
        k2 = f(t + dt/2, x + k1*dt/2)
        k3 = f(t + dt/2, x + k2*dt/2)
        k4 = f(t + dt, x + k3*dt)
        x = x + (dt/6.0) * (k1 + 2*k2 + 2*k3 + k4)
        t = t + dt
        expected_trajectory.append((t, x))

    expected_root = None
    for i in range(len(expected_trajectory)-1):
        t1, x1 = expected_trajectory[i]
        t2, x2 = expected_trajectory[i+1]
        if x1 * x2 <= 0:
            expected_root = t1 - x1 * (t2 - t1) / (x2 - x1)
            break

    return expected_trajectory, expected_root

def test_simulate_c_exists():
    assert os.path.isfile('/home/user/simulate.c'), "/home/user/simulate.c does not exist. You must write your C code here."

def test_root_txt():
    root_file = '/home/user/root.txt'
    assert os.path.isfile(root_file), f"{root_file} does not exist. Did you run your C program?"

    _, expected_root = get_expected_data()

    with open(root_file, 'r') as f:
        content = f.read().strip()

    try:
        agent_root = float(content)
    except ValueError:
        pytest.fail(f"Could not parse float from {root_file}. Content: '{content}'")

    assert abs(agent_root - expected_root) <= 1e-4, f"Root mismatch. Expected approx {expected_root:.4f}, got {agent_root:.4f}"

def test_trajectory_csv():
    traj_file = '/home/user/trajectory.csv'
    assert os.path.isfile(traj_file), f"{traj_file} does not exist. Did you run your C program?"

    expected_trajectory, _ = get_expected_data()

    with open(traj_file, 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) > 0, f"{traj_file} is empty."
    assert lines[0].replace(" ", "") == "t,x", f"Missing or incorrect header in {traj_file}. Expected 't,x', got '{lines[0]}'"

    expected_len = len(expected_trajectory) + 1
    assert len(lines) == expected_len, f"Expected {expected_len} lines in {traj_file}, got {len(lines)}"

    for i, line in enumerate(lines[1:]):
        parts = line.split(',')
        assert len(parts) == 2, f"Invalid format at line {i+2} in {traj_file}: '{line}'"

        try:
            agent_t = float(parts[0])
            agent_x = float(parts[1])
        except ValueError:
            pytest.fail(f"Could not parse floats at line {i+2} in {traj_file}: '{line}'")

        exp_t, exp_x = expected_trajectory[i]

        assert abs(agent_t - exp_t) <= 1e-4, f"Time mismatch at step {i}. Expected {exp_t:.4f}, got {agent_t:.4f}"
        assert abs(agent_x - exp_x) <= 1e-3, f"Trajectory x mismatch at step {i} (t={exp_t:.4f}). Expected {exp_x:.4f}, got {agent_x:.4f}"
TEST_EOF

rm -f /home/user/trajectory.csv /home/user/root.txt /tmp/verifier_simulate
artifact_ok=1

if [ ! -f /home/user/simulate.c ]; then
    artifact_ok=0
elif ! gcc /home/user/simulate.c -o /tmp/verifier_simulate -lm; then
    artifact_ok=0
elif ! timeout 10s runuser -u user -- /tmp/verifier_simulate; then
    artifact_ok=0
fi

pytest_ok=1
if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    pytest_ok=0
fi

if [ "$artifact_ok" -eq 1 ] && [ "$pytest_ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
