#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess

import pytest


def minimum_strictly_stable_m(alpha, n):
    # r = alpha * (0.5 / M) * N^2 must be strictly less than 0.5,
    # equivalently M > alpha * N^2.
    m = math.floor(alpha * n**2) + 1
    while alpha * (0.5 / m) * n**2 >= 0.5:
        m += 1
    return max(1, m)


def simulate(n, m, alpha):
    dx = 1.0 / n
    dt = 0.5 / m
    r = alpha * dt / (dx * dx)
    u = [math.sin(math.pi * i * dx) for i in range(n + 1)]
    for _ in range(m):
        u_new = u[:]
        for i in range(1, n):
            u_new[i] = u[i] + r * (u[i + 1] - 2.0 * u[i] + u[i - 1])
        u = u_new
    return [(i * dx, u[i]) for i in range(n + 1)]


def get_expected_solution():
    alpha = 0.04
    for n in range(10, 100):
        m = minimum_strictly_stable_m(alpha, n)
        assert alpha * (0.5 / m) * n**2 < 0.5

        values = simulate(n, m, alpha)
        max_err = max(
            abs(u - math.sin(math.pi * x) * math.exp(-alpha * math.pi**2 * 0.5))
            for x, u in values
        )
        if max_err < 0.005:
            return f"{alpha},{n},{m}"
    raise AssertionError("No expected solution was found")


def run_and_check_simulation(n, m, alpha):
    exe_path = "/home/user/heat_sim"
    result = subprocess.run(
        [exe_path, str(n), str(m), str(alpha)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, result.stderr

    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert lines and lines[0] == "x,u", "Simulation output must begin with the x,u header"
    assert len(lines) == n + 2, f"Expected {n + 1} data rows, got {len(lines) - 1}"

    actual = []
    for line in lines[1:]:
        parts = line.split(",")
        assert len(parts) == 2, f"Malformed simulation row: {line!r}"
        x, u = map(float, parts)
        assert math.isfinite(x) and math.isfinite(u), f"Non-finite output row: {line!r}"
        actual.append((x, u))

    expected = simulate(n, m, alpha)
    for (actual_x, actual_u), (expected_x, expected_u) in zip(actual, expected):
        assert actual_x == pytest.approx(expected_x, abs=2e-5)
        assert actual_u == pytest.approx(expected_u, abs=2e-5)


def test_executable_compiled():
    exe_path = "/home/user/heat_sim"
    assert os.path.exists(exe_path), f"Executable {exe_path} was not found."
    assert os.path.isfile(exe_path), f"{exe_path} is not a file."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."

    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exe_path} is not a compiled ELF executable."

    # Exercise the submitted executable on both the required solution parameters
    # and unpredictable inputs, deriving all expected values independently.
    run_and_check_simulation(10, minimum_strictly_stable_m(0.04, 10), 0.04)
    for _ in range(3):
        n = 10 + secrets.randbelow(16)
        alpha = (1 + secrets.randbelow(10)) / 100.0
        m = minimum_strictly_stable_m(alpha, n) + secrets.randbelow(5)
        run_and_check_simulation(n, m, alpha)


def test_solution_file():
    sol_path = "/home/user/solution.txt"
    assert os.path.exists(sol_path), f"Solution file {sol_path} was not found."

    with open(sol_path, "r") as f:
        agent_solution = f.read().strip()

    expected_solution = get_expected_solution()

    try:
        agent_parts = [p.strip() for p in agent_solution.split(",")]
        expected_parts = expected_solution.split(",")

        assert float(agent_parts[0]) == float(expected_parts[0]), f"Expected alpha={expected_parts[0]}, got {agent_parts[0]}"
        assert int(agent_parts[1]) == int(expected_parts[1]), f"Expected N={expected_parts[1]}, got {agent_parts[1]}"
        assert int(agent_parts[2]) == int(expected_parts[2]), f"Expected M={expected_parts[2]}, got {agent_parts[2]}"
    except Exception as e:
        pytest.fail(f"Failed to parse or validate solution.txt. Expected format 'alpha,N,M' with values {expected_solution}. Got: '{agent_solution}'. Error: {e}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
